/*
Licensed Under BSD

Copyright (c) 2013, Daniel Holden
Modifications 2019 by Vidar Hokstad
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

typedef struct {
  void *ptr;
  size_t size, hash;
  unsigned char leaf : 1;
  unsigned char mark : 1;
} tgc_ptr_t;

typedef struct {
  void *stack_bottom;
  void *roots_start;
  void *roots_end;
  uintptr_t minptr, maxptr;
  tgc_ptr_t *items, *frees;
  double loadfactor, sweepfactor;
  size_t nitems, nslots, mitems, nfrees;
} tgc_t;

tgc_t gc;

static size_t tgc_hash(void *ptr) { return ((uintptr_t)ptr) >> 3; }
static unsigned short is_marked(size_t i) { return gc.items[i].mark; }
static unsigned short is_leaf(size_t i)   { return gc.items[i].leaf; }
static void clear_mark(size_t i) { gc.items[i].mark = 0; }
static void set_mark(size_t i)   { gc.items[i].mark = 1; }

static size_t tgc_probe(size_t i, size_t h) {
  long v = i - (h-1);
  if (v < 0) { v = gc.nslots + v; }
  return v;
}

static tgc_ptr_t *tgc_get_ptr(void *ptr) {
  size_t i, j, h;
  i = tgc_hash(ptr) % gc.nslots; j = 0;
  while (1) {
    h = gc.items[i].hash;
    if (h == 0 || j > tgc_probe(i, h)) { return NULL; }
    if (gc.items[i].ptr == ptr) { return &gc.items[i]; }
    i = (i+1) % gc.nslots; j++;
  }
  return NULL;
}

static void tgc_add_ptr(void *ptr, size_t size, int leaf) {

  tgc_ptr_t item;
  size_t i = tgc_hash(ptr) % gc.nslots;
  size_t j = 0;

  item.ptr = ptr;
  item.leaf = leaf;
  item.mark = 0;
  item.size = size;
  item.hash = i+1;

  while (1) {
    size_t h = gc.items[i].hash;
    if (h == 0) { gc.items[i] = item; return; }
    if (gc.items[i].ptr == item.ptr) { return; }
    size_t p = tgc_probe(i, h);
    if (j >= p) {
      tgc_ptr_t tmp = gc.items[i];
      gc.items[i] = item;
      item = tmp;
      j = p;
    }
    i = (i+1) % gc.nslots; j++;
  }
}

static void tgc_rem_ptr(void *ptr) {
  if (gc.nitems == 0) { return; }

  size_t i, j, h, nj, nh;
  for (i = 0; i < gc.nfrees; i++) {
    if (gc.frees[i].ptr == ptr) { gc.frees[i].ptr = NULL; }
  }

  i = tgc_hash(ptr) % gc.nslots; j = 0;

  while (1) {
    h = gc.items[i].hash;
    if (h == 0 || j > tgc_probe(i, h)) { return; }
    if (gc.items[i].ptr == ptr) {
      memset(&gc.items[i], 0, sizeof(tgc_ptr_t));
      j = i;
      while (1) {
        nj = (j+1) % gc.nslots;
        nh = gc.items[nj].hash;
        if (nh != 0 && tgc_probe(nj, nh) > 0) {
          memcpy(&gc.items[ j], &gc.items[nj], sizeof(tgc_ptr_t));
          memset(&gc.items[nj],              0, sizeof(tgc_ptr_t));
          j = nj;
        } else {
          break;
        }
      }
      gc.nitems--;
      return;
    }
    i = (i+1) % gc.nslots; j++;
  }
}


enum {
  TGC_PRIMES_COUNT = 24
};

static const size_t tgc_primes[TGC_PRIMES_COUNT] = {
  0,       1,       5,       11,
  23,      53,      101,     197,
  389,     683,     1259,    2417,
  4733,    9371,    18617,   37097,
  74093,   148073,  296099,  592019,
  1100009, 2200013, 4400021, 8800019
};

static size_t tgc_ideal_size(size_t size) {
  size_t i, last;
  size = (size_t)((double)(size+1) / gc.loadfactor);
  for (i = 0; i < TGC_PRIMES_COUNT; i++) {
    if (tgc_primes[i] >= size) { return tgc_primes[i]; }
  }
  last = tgc_primes[TGC_PRIMES_COUNT-1];
  for (i = 0;; i++) {
    if (last * i >= size) { return last * i; }
  }
  return 0;
}

static int tgc_rehash(size_t new_size) {

  size_t i;
  tgc_ptr_t *old_items = gc.items;
  size_t old_size = gc.nslots;

  gc.nslots = new_size;
  gc.items = calloc(gc.nslots, sizeof(tgc_ptr_t));

  if (gc.items == NULL) {
    gc.nslots = old_size;
    gc.items = old_items;
    return 0;
  }

  for (i = 0; i < old_size; i++) {
    if (old_items[i].hash != 0) {
      tgc_add_ptr(
        old_items[i].ptr,   old_items[i].size, 
        old_items[i].leaf);
    }
  }

  free(old_items);
  return 1;
}

static int tgc_resize_more() {
  size_t new_size = tgc_ideal_size(gc.nitems);
  size_t old_size = gc.nslots;
  return (new_size > old_size) ? tgc_rehash(new_size) : 1;
}

static int tgc_resize_less() {
  size_t new_size = tgc_ideal_size(gc.nitems);
  size_t old_size = gc.nslots;
  return (new_size < old_size) ? tgc_rehash(new_size) : 1;
}

static void tgc_mark_ptr(void *ptr) {

  size_t i, j, h;

  if ((uintptr_t)ptr < gc.minptr
  ||  (uintptr_t)ptr > gc.maxptr) { return; }

  i = tgc_hash(ptr) % gc.nslots; j = 0;

  while (1) {
    h = gc.items[i].hash;
    if (h == 0 || j > tgc_probe(i, h)) { return; }
    if (ptr == gc.items[i].ptr) {
      if (is_marked(i)) { return; }
      set_mark(i);
      if (is_leaf(i)) { return; }
      for (size_t k = 0; k < gc.items[i].size/sizeof(void*); k++) {
        tgc_mark_ptr(((void**)gc.items[i].ptr)[k]);
      }
      return;
    }
    i = (i+1) % gc.nslots; j++;
  }
}

static void tgc_mark_static_roots() {
  void *bot, *top, *p;
  bot = gc.roots_start; top = gc.roots_end;

  if (bot == 0) return;

  for (p = top; p >= bot; p = ((char*)p) - sizeof(void*)) {
    tgc_mark_ptr(*((void**)p));
  }
}

static void tgc_mark_stack() {
  void * bot = gc.stack_bottom;
  void * top = &bot;
  for (void * p = top; p <= bot; p = ((char*)p) + sizeof(void*)) {
    tgc_mark_ptr(*((void**)p));
  }
}

static void tgc_mark() {
  jmp_buf env;
  void (*volatile mark_stack)() = tgc_mark_stack;
  if (gc.nitems == 0) { return; }

  tgc_mark_static_roots();

  memset(&env, 0, sizeof(jmp_buf));
  setjmp(env);
  mark_stack(gc);
}

static void tgc_sweep() {
  size_t i, j, k, nj, nh;
  if (gc.nitems == 0) { return; }

  gc.nfrees = 0;
  for (i = 0; i < gc.nslots; i++) {
    if (gc.items[i].hash == 0) { continue; }
    if (is_marked(i))      { continue; }
    gc.nfrees++;
  }

  gc.frees = realloc(gc.frees, sizeof(tgc_ptr_t) * gc.nfrees);
  if (gc.frees == NULL) { return; }

  i = 0; k = 0;
  while (i < gc.nslots) {
    if (gc.items[i].hash == 0) { i++; continue; }
    if (is_marked(i))      { i++; continue; }
    gc.frees[k] = gc.items[i]; k++;
    memset(&gc.items[i], 0, sizeof(tgc_ptr_t));

    j = i;
    while (1) {
      nj = (j+1) % gc.nslots;
      nh = gc.items[nj].hash;
      if (nh != 0 && tgc_probe(nj, nh) > 0) {
        memcpy(&gc.items[ j], &gc.items[nj], sizeof(tgc_ptr_t));
        memset(&gc.items[nj],             0, sizeof(tgc_ptr_t));
        j = nj;
      } else {
        break;
      }
    }
    gc.nitems--;
  }

  for (i = 0; i < gc.nslots; i++) {
    if (gc.items[i].hash == 0) { continue; }
    clear_mark(i);
  }
  tgc_resize_less(gc);
  gc.mitems = gc.nitems + (size_t)(gc.nitems * gc.sweepfactor) + 1;

  for (i = 0; i < gc.nfrees; i++) {
    if (gc.frees[i].ptr) free(gc.frees[i].ptr);
  }

  free(gc.frees);
  gc.frees = NULL;
  gc.nfrees = 0;
}

void tgc_start(void *stk, void * bot, void * top) {
  memset(&gc, 0, sizeof(tgc_t));
  gc.roots_start = bot;
  gc.roots_end = top;
  gc.stack_bottom = stk;
  gc.minptr = UINTPTR_MAX;
  gc.loadfactor = 0.4;
  gc.sweepfactor = 2;
}

void tgc_stop() {
  tgc_sweep();
  free(gc.items);
  free(gc.frees);
}

void *tgc_add(void *ptr, size_t size, int leaf) {
  gc.nitems++;
  gc.maxptr = ((uintptr_t)ptr) + size > gc.maxptr ?
    ((uintptr_t)ptr) + size : gc.maxptr;
  gc.minptr = ((uintptr_t)ptr)        < gc.minptr ?
    ((uintptr_t)ptr)        : gc.minptr;

  if (tgc_resize_more()) {
    tgc_add_ptr(ptr, size, leaf);
    if (gc.nitems > gc.mitems) {
      tgc_mark();
      tgc_sweep();
    }
    return ptr;
  } else {
    gc.nitems--;
    free(ptr);
    return NULL;
  }
}

static void tgc_rem(void *ptr) {
  tgc_rem_ptr(ptr);
  tgc_resize_less();
}

void *tgc_realloc(void *ptr, size_t size) {
  void *qtr = realloc(ptr, size);

  if (qtr == NULL) {
    tgc_rem(ptr);
    return qtr;
  }

  if (ptr == NULL) {
    tgc_add(qtr, size, 0);
    return qtr;
  }

  tgc_ptr_t *p  = tgc_get_ptr(ptr);

  if (p && qtr == ptr) {
    p->size = size;
    return qtr;
  }

  if (p && qtr != ptr) {
    unsigned short leaf = p->leaf;
    tgc_rem(ptr);
    tgc_add(qtr, size, leaf);
    return qtr;
  }

  return NULL;
}
