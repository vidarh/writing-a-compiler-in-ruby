/*
Licensed Under BSD

Copyright (c) 2013, Daniel Holden
Modifications 2019-2026 by Vidar Hokstad
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of the FreeBSD Project.
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <setjmp.h>
#include <signal.h>

/* Ignore SIGPIPE process-wide (as MRI does). */
__attribute__((constructor))
static void __rt_ignore_sigpipe(void) {
  signal(SIGPIPE, SIG_IGN);
}

/* ---------------------------------------------------------------------------
   ARENA-BASED conservative mark-sweep GC.

   Objects are bump-allocated from large arenas instead of individually
   malloc'd + tracked in a per-object pointer HASHTABLE. GC membership ("is
   this candidate word a managed object pointer?") is a range-check against the
   arenas + an object-start bitmap, replacing the hashtable that cost a
   hash+Robin-Hood insert on EVERY allocation and ~2.5x its live size in slots.

   Each object is preceded by an 8-byte header holding
     szf = (size << 2) | (leaf << 1) | mark
   (size in the top 30 bits -- objects are < 1GB; leaf in bit 1; mark in bit 0).
   The Ruby-visible pointer points at the data AFTER the header, 8-byte aligned.

   Per arena: an object-start bitmap, 1 bit per 8 bytes, set at each LIVE
   object's word index. Dead objects are swept onto per-size-class free lists
   (their object-start bit cleared so a stray pointer can't resurrect them) and
   reused before bumping. The header (hence size) is preserved for freed slots
   so the linear sweep walk can always step slot-to-slot.
   --------------------------------------------------------------------------- */

#define HDR         ((size_t)8)                         /* header bytes before each object (keeps 8-byte align) */
#define ALIGNUP(n)  (((n) + (size_t)7) & ~((size_t)7))
#define ARENA_BYTES ((size_t)256 * 1024 * 1024)         /* 256MB arenas: keep the arena count (hence the
                                                            membership scan) tiny; calloc is lazily paged so an
                                                            unused arena costs ~no real memory. */
#define MAXCLASS    ((size_t)16384)                      /* exact-fit free lists for objects up to 128KB */

#define SZF_SIZE(x)        ((size_t)((x) >> 2))
#define SZF_MAKE(sz, leaf) ((uint32_t)(((uint32_t)(sz) << 2) | ((leaf) ? 2u : 0u)))

typedef struct arena {
  struct arena *next;
  char    *base;      /* start of the object region */
  char    *cur;       /* bump pointer (== end of allocated region) */
  char    *end;       /* end of the buffer */
  uint8_t *objstart;  /* 1 bit per 8 bytes: set at each live object's word index */
} arena_t;

typedef struct {
  void *stack_bottom, *roots_start, *roots_end;
  uintptr_t minptr, maxptr;
  arena_t *arenas;
  void *freelist[MAXCLASS];
  double sweepfactor;
  size_t nitems, mitems;
} tgc_t;

static tgc_t gc;

/* Lightweight instrumentation (reported at exit when TGC_STATS is set). */
static size_t g_nallocs = 0, g_ncollects = 0;

/* --- header accessors (obj points at the DATA; header is the 8 bytes before) --- */
static inline uint32_t *hdr_of(void *obj) { return (uint32_t*)((char*)obj - HDR); }
static inline int    obj_marked(void *obj) { return *hdr_of(obj) & 1u; }
static inline void   obj_setmark(void *obj) { *hdr_of(obj) |= 1u; }
static inline void   obj_clrmark(void *obj) { *hdr_of(obj) &= ~1u; }
static inline int    obj_leaf(void *obj)   { return (*hdr_of(obj) >> 1) & 1u; }
static inline size_t obj_size(void *obj)   { return SZF_SIZE(*hdr_of(obj)); }

/* --- object-start bitmap, indexed by (obj - arena->base) / 8 --- */
static inline void bm_set(arena_t *a, size_t i) { a->objstart[i>>3] |= (uint8_t)(1u << (i&7)); }
static inline void bm_clr(arena_t *a, size_t i) { a->objstart[i>>3] &= (uint8_t)~(1u << (i&7)); }
static inline int  bm_get(arena_t *a, size_t i) { return (a->objstart[i>>3] >> (i&7)) & 1; }

static arena_t *arena_new(size_t need) {
  size_t bytes = ARENA_BYTES;
  if (HDR + ALIGNUP(need) > bytes) { bytes = ALIGNUP(HDR + ALIGNUP(need)); } /* oversized single object */

  arena_t *a = (arena_t*)calloc(1, sizeof(arena_t));
  if (!a) { return NULL; }
  a->base = (char*)calloc(1, bytes);
  if (!a->base) { free(a); return NULL; }
  a->objstart = (uint8_t*)calloc(1, (bytes / 8) / 8 + 1);
  if (!a->objstart) { free(a->base); free(a); return NULL; }
  a->cur = a->base;
  a->end = a->base + bytes;
  a->next = gc.arenas;
  gc.arenas = a;

  if ((uintptr_t)a->base < gc.minptr) { gc.minptr = (uintptr_t)a->base; }
  if ((uintptr_t)a->end  > gc.maxptr) { gc.maxptr = (uintptr_t)a->end; }
  return a;
}

/* Arena whose allocated region contains data pointer p, or NULL. */
static arena_t *arena_of(void *p) {
  if ((uintptr_t)p < gc.minptr || (uintptr_t)p >= gc.maxptr) { return NULL; }
  for (arena_t *a = gc.arenas; a; a = a->next) {
    if ((char*)p >= a->base && (char*)p < a->cur) { return a; }
  }
  return NULL;
}

static void tgc_collect(void);

void *tgc_alloc(size_t size, int leaf) {
  /* Slot size. Non-leaf objects (arrays/objects/closures -- the ~90% majority) are fixed-size and never
     write past `size`, so no padding. LEAF (String) buffers get an 8-byte slack word as a C-interop safety
     margin (a NUL terminator could be written at [size] when size%8==0); selftest-c + a 100k-string stress
     pass without even this, but the spec sweep (blocked) exercises more string paths, so keep the margin.
     The free list is keyed by the FINAL slot size, so leaf/non-leaf of a given class share slots safely. */
  size_t asz = ALIGNUP(size) + (leaf ? (size_t)8 : (size_t)0);
  if (asz < 8) { asz = 8; }   /* min slot: free-list link + obj strictly < cur */
  size_t cls = asz / 8;
  void *obj = NULL;
  arena_t *a;

  if (cls < MAXCLASS && gc.freelist[cls]) {
    /* reuse a freed slot of the exact class */
    obj = gc.freelist[cls];
    gc.freelist[cls] = *(void**)obj;              /* pop (link stored in the object's first word) */
    a = arena_of(obj);
    bm_set(a, ((size_t)((char*)obj - a->base)) / 8);
    memset(obj, 0, size);                          /* reused: slot holds stale data + the free-list link */
  } else {
    /* bump-allocate. Fresh arena memory is already zero (the arena is calloc'd and bump only moves
       FORWARD into never-touched bytes), so skip the memset here -- it was ~8GB of redundant zeroing
       across the ~200M allocations of a self-compile. */
    a = gc.arenas;
    size_t total = HDR + asz;
    if (!a || (size_t)(a->end - a->cur) < total) {
      a = arena_new(size);
      if (!a) { return NULL; }
    }
    char *slot = a->cur;
    a->cur += total;
    obj = slot + HDR;
    bm_set(a, ((size_t)((char*)obj - a->base)) / 8);
  }

  *hdr_of(obj) = SZF_MAKE(size, leaf);            /* size + leaf, mark = 0 */
  gc.nitems++;
  g_nallocs++;

  if (gc.nitems > gc.mitems) { tgc_collect(); }   /* obj is a live local -> conservatively kept on the stack */
  return obj;
}

/* --- marking (iterative, explicit gray stack) ---
   The mark must NOT recurse per field: a deep object graph (a long linked list, deeply-nested arrays)
   would overflow the C stack and SIGSEGV. An explicit gray stack keeps the depth on the heap. */
static void **g_gray = NULL;
static size_t g_gray_cap = 0, g_gray_top = 0;

/* Is p an unmarked managed object start? (8-aligned in an arena with its object-start bit set.)
   The 8-byte ALIGNMENT guard is mandatory: (p-base)/8 would truncate a misaligned candidate (tagged
   fixnum / interior / garbage word) onto some real object's bitmap index -> false positive -> garbage
   header -> OOB. The old exact-match hashtable was immune; the bitmap is not. */
static inline int obj_is_unmarked(void *p) {
  if ((uintptr_t)p & 7u) { return 0; }
  arena_t *a = arena_of(p);
  if (!a) { return 0; }
  size_t i = ((size_t)((char*)p - a->base)) / 8;
  return bm_get(a, i) && !obj_marked(p);
}

/* Recursive fallback used ONLY when the gray stack can't grow (OOM) -- correctness over stack-safety in
   an already-failing scenario. */
static void tgc_mark_recursive(void *p) {
  if (!obj_is_unmarked(p)) { return; }
  obj_setmark(p);
  if (obj_leaf(p)) { return; }
  size_t words = obj_size(p) / sizeof(void*);
  void **f = (void**)p;
  for (size_t k = 0; k < words; k++) { tgc_mark_recursive(f[k]); }
}

/* Mark p; push it (if non-leaf) for later field scanning. */
static void gray_push(void *p) {
  if (!obj_is_unmarked(p)) { return; }
  obj_setmark(p);
  if (obj_leaf(p)) { return; }
  if (g_gray_top >= g_gray_cap) {
    size_t ncap = g_gray_cap ? g_gray_cap * 2 : 8192;
    void **n = (void**)realloc(g_gray, ncap * sizeof(void*));
    if (!n) {                                       /* OOM: scan p's fields recursively (rare, terminal) */
      size_t words = obj_size(p) / sizeof(void*);
      void **f = (void**)p;
      for (size_t k = 0; k < words; k++) { tgc_mark_recursive(f[k]); }
      return;
    }
    g_gray = n; g_gray_cap = ncap;
  }
  g_gray[g_gray_top++] = p;
}

static void tgc_mark_ptr(void *p) {
  gray_push(p);
  while (g_gray_top > 0) {
    void *o = g_gray[--g_gray_top];
    size_t words = obj_size(o) / sizeof(void*);
    void **f = (void**)o;
    for (size_t k = 0; k < words; k++) { gray_push(f[k]); }
  }
}

static void tgc_mark_static_roots(void) {
  void *bot, *top, *p;
  bot = gc.roots_start; top = gc.roots_end;
  if (bot == 0) { return; }
  for (p = top; p >= bot; p = ((char*)p) - sizeof(void*)) {
    tgc_mark_ptr(*((void**)p));
  }
}

static void tgc_mark_stack(void) {
  void *bot = gc.stack_bottom;
  void *top = &bot;
  for (void *p = top; p <= bot; p = ((char*)p) + sizeof(void*)) {
    tgc_mark_ptr(*((void**)p));
  }
}

static void tgc_mark(void) {
  jmp_buf env;
  void (*volatile mark_stack)(void) = tgc_mark_stack;
  if (gc.nitems == 0) { return; }
  tgc_mark_static_roots();
  memset(&env, 0, sizeof(jmp_buf));
  setjmp(env);
  mark_stack();
}

/* --- sweep: walk every arena slot-by-slot; free unmarked, clear marks --- */
static void tgc_sweep(void) {
  for (arena_t *a = gc.arenas; a; a = a->next) {
    char *p = a->base;
    while (p < a->cur) {
      void *obj = p + HDR;
      size_t asz = ALIGNUP(obj_size(obj)) + (obj_leaf(obj) ? (size_t)8 : (size_t)0);  /* MUST match tgc_alloc */
      if (asz < 8) { asz = 8; }
      size_t idx = ((size_t)((char*)obj - a->base)) / 8;
      if (bm_get(a, idx)) {                         /* a live slot */
        if (obj_marked(obj)) {
          obj_clrmark(obj);                         /* survives; reset for next cycle */
        } else {
          bm_clr(a, idx);                           /* dead: unlink from membership... */
          size_t cls = asz / 8;
          if (cls < MAXCLASS) {                     /* ...and onto its size-class free list */
            *(void**)obj = gc.freelist[cls];
            gc.freelist[cls] = obj;
          }
          gc.nitems--;
        }
      }
      p += HDR + asz;
    }
  }
}

static void tgc_collect(void) {
  g_ncollects++;
  tgc_mark();
  tgc_sweep();
  gc.mitems = gc.nitems + (size_t)(gc.nitems * gc.sweepfactor) + 1;
}

void tgc_start(void *stk, void *bot, void *top) {
  memset(&gc, 0, sizeof(tgc_t));
  gc.roots_start = bot;
  gc.roots_end = top;
  gc.stack_bottom = stk;
  gc.minptr = UINTPTR_MAX;
  gc.maxptr = 0;
  /* sweepfactor governs how much the live set may grow before the next mark+sweep
     (mitems = nitems*(1+sweepfactor)). MEASURED (2026-07-10, self-hosted compile of test/selftest.rb):
     the old "batch process -> collect rarely" assumption was WRONG -- there is a lot of TRANSIENT garbage
     (temporaries) between collections, and the sweep walks the whole heap, so a bigger heap makes each
     sweep costlier AND balloons RSS. Lower factor -> smaller heap -> cheaper sweeps + far less RSS:
     sf=16 was 507MB, sf=8 is 360MB (-29%) with equal-or-better wall-clock (sf=4 turns over on collect
     overhead). 8 is the sweet spot. Env override (TGC_SWEEP) for tuning. */
  gc.sweepfactor = 8;
  { const char *s = getenv("TGC_SWEEP"); if (s && *s) { gc.sweepfactor = atof(s); } }
}

void tgc_stop(void) {
  if (getenv("TGC_STATS")) {
    size_t narenas = 0; for (arena_t *x = gc.arenas; x; x = x->next) { narenas++; }
    fprintf(stderr, "TGC: allocs=%zu collects=%zu live=%zu arenas=%zu sweepfactor=%g\n",
            g_nallocs, g_ncollects, gc.nitems, narenas, gc.sweepfactor);
  }
  arena_t *a = gc.arenas;
  while (a) {
    arena_t *n = a->next;
    free(a->objstart);
    free(a->base);
    free(a);
    a = n;
  }
  gc.arenas = NULL;
  free(g_gray); g_gray = NULL; g_gray_cap = 0; g_gray_top = 0;
}

/* Grow (or first-allocate) a buffer. Returns a NEW object; the old one becomes unreachable and is swept.
   The old pointer stays live across the possible collection in tgc_alloc because the caller holds it on
   its own stack/regs (and tgc_realloc's own `ptr` local is on the scanned C stack). */
void *tgc_realloc(void *ptr, size_t size) {
  if (ptr == NULL) { return tgc_alloc(size, 0); }

  size_t old = obj_size(ptr);
  int leaf = obj_leaf(ptr);
  void *n = tgc_alloc(size, leaf);
  if (n == NULL) { return NULL; }
  memcpy(n, ptr, old < size ? old : size);
  return n;
}
