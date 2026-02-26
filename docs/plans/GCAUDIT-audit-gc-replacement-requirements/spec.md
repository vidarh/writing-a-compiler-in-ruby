GCAUDIT
Created: 2026-02-26

# Audit GC Replacement Requirements for PURERB

[PURERB] Investigate why the C garbage collector is currently disabled, document the
`tgc.c` API surface from compiled programs' perspective, profile memory usage during
self-compilation, and produce `docs/gc-replacement-requirements.md` as the specification
for a future Ruby GC implementation.

## Goal Reference

[PURERB](../../goals/PURERB-pure-ruby-runtime.md)

## Prior Plans

No prior plans in `docs/plans/` or `docs/plans/archived/` target [PURERB](../../goals/PURERB-pure-ruby-runtime.md)
directly. [LOCALDEV](../../plans/archived/LOCALDEV-docker-free-local-compilation/spec.md)
(IMPLEMENTED) mentioned PURERB as a secondary goal and removed the Docker requirement as
"the intermediate step — remove Docker from the workflow, before later removing GAS/LD from
the pipeline." No plan has addressed the GC replacement, the GAS/LD dependency, or any
part of PURERB's core requirements. This is the first PURERB plan.

## Root Cause

The C garbage collector (`tgc.c`, 387 lines, BSD-licensed) is the sole non-Ruby component
in the compiled runtime, making it the primary blocker for the [PURERB](../../goals/PURERB-pure-ruby-runtime.md)
goal. However, the GC is currently **disabled**: both initialization calls in
[lib/core/base.rb](../../../lib/core/base.rb) are commented out:

```ruby
# lib/core/base.rb:22
#%s(tgc_start (stackframe) __roots_start __roots_end)

# lib/core/base.rb:53
#%s(atexit tgc_stop)
```

The `__alloc` function at [lib/core/base.rb:24-30](../../../lib/core/base.rb) uses raw
`calloc` without registering allocations with the GC. This means compiled programs leak
all heap memory — no collection ever runs. The README confirms: *"Self-hosting was achieved,
but is slow and GC is disabled."*

**Why this is the root cause to investigate:** The PURERB goal requires replacing `tgc.c`
with a Ruby implementation. But replacing something that's already disabled — without
understanding *why* it was disabled and *what would break if re-enabled* — risks designing
a Ruby GC that solves the wrong problem. The root causes of the current GC disablement
(stack scanning fragility? conservative pointer confusion with tagged integers? timing
issues?) directly constrain what a Ruby replacement must handle. Without this understanding,
any Ruby GC design will be speculation.

**The circular dependency problem** (documented in the PURERB goal): A Ruby GC implementation
itself allocates Ruby objects during collection. These GC-internal allocations would need to
be managed by the GC, creating a self-referential loop. This is a known hard problem that
constrains the design. Understanding what memory the current `__alloc` path is used for
(Ruby objects, C arrays, vtable slots?) is essential context for choosing a mitigation
strategy (arena allocator for GC temporaries, or mark-on-create).

**The second blocker — GAS/LD dependency** — is related but separate. The README mentions
"A Ruby prototype x86 -> ELF binary assembler has shown we can drop the gas/ld dependency."
This plan does not address the assembler; it focuses exclusively on the GC blocker because:
1. GC is the simpler blocker (387 lines of C vs. full x86 instruction encoding)
2. Understanding GC requirements is prerequisite to designing a Ruby GC
3. Scoping both into one plan would dilute the investigation

## Infrastructure Cost

Low. This is primarily a research and documentation plan:

- Read and analyze [tgc.c](../../../tgc.c) and [lib/core/base.rb](../../../lib/core/base.rb)
- Make two one-line changes to re-enable GC (the commented-out `tgc_start` and `tgc_stop` calls)
- Run `make selftest` to observe what breaks
- Use Valgrind (`make valgrind`) to measure allocation volume
- Write `docs/gc-replacement-requirements.md`

No new dependencies. No build system changes. Validation uses existing `make selftest` and
`make valgrind` commands. If re-enabling GC breaks selftest, the changes are reverted and
the breakage is documented (the information is still valuable). The only new file created
is the requirements document.

## Scope

**In scope:**

1. **Understand why GC is disabled**: Uncomment `tgc_start` and `tgc_stop` in
   [lib/core/base.rb](../../../lib/core/base.rb). Run `make selftest`. Observe whether
   it passes or crashes. If it crashes, use the crash output and Valgrind to identify the
   root cause (e.g., conservative GC misidentifying tagged integers as pointers, stack
   scanning overreach, GC overhead causing timeouts). Document findings.

2. **Document `tgc.c` API surface**: Enumerate every function that compiled programs can
   call, with its signature and semantics:
   - `tgc_start(void *stk, void *bot, void *top)` — initialize GC
   - `tgc_stop()` — finalize (sweep remaining)
   - `tgc_add(void *ptr, size_t size, int leaf)` — register an allocation
   - `tgc_realloc(void *ptr, size_t size)` — realloc a tracked pointer
   - Any other exported functions

3. **Trace allocation call sites**: In the compiler source, identify every call to `__alloc`,
   `__alloc_mem`, `__alloc_leaf`, `__alloc_env`, `__realloc`, `calloc`, and `malloc` from
   generated code. Classify what each allocation is for (object slots, vtable, array storage,
   string buffer, closure env, etc.). This reveals what a Ruby GC must manage.

4. **Measure allocation volume**: Run `make selftest` under Valgrind (`make valgrind`) and
   capture the total heap allocation count and volume. This answers: "how many allocations
   does a compilation make, and how large are they?" If the answer is "10,000 allocations
   totaling 5 MB," GC overhead matters. If it's "100 allocations totaling 100 KB," a simple
   malloc-and-never-free scheme might be adequate for the near term.

5. **Document the tagged-pointer scheme**: The compiler uses tagged integers (least significant
   bit set = fixnum). Document how this interacts with conservative GC pointer scanning — this
   is the most likely reason the GC was disabled (half of all integers look like valid pointers
   to a conservative scanner). Quantify the impact: what fraction of fixnums would be
   misidentified as heap pointers in a typical program?

6. **Produce `docs/gc-replacement-requirements.md`**: Synthesize findings into:
   - Current state: why GC is disabled, what breaks if re-enabled
   - API surface: functions a Ruby GC must implement
   - Allocation taxonomy: what types of objects the GC must manage
   - Allocation volume: measured allocation counts from Valgrind
   - Tagged-pointer interaction: how fixnums affect conservative scanning
   - Two or more concrete approaches for a Ruby GC replacement, with trade-offs:
     * **Approach A: Re-enable and fix the C GC** (patch `tgc.c` for tagged-pointer awareness) as an interim step before Ruby replacement
     * **Approach B: Simple Ruby allocator without collection** (arena-style, free-at-process-end) — suitable since compilations are short-lived
     * **Approach C: Full Ruby mark-and-sweep** with arena allocator for GC temporaries (addresses circular dependency)
   - Recommendation: which approach to implement first

**Out of scope:**
- Implementing any Ruby GC (that is the next plan after this audit)
- The GAS/LD assembler dependency (separate PURERB concern, requires different investigation)
- Modifying the compiler's object model or tagging scheme
- Adding GC to the core library methods (e.g., `String#dup` tracking)

## Expected Payoff

**Immediate:**
- [PURERB](../../goals/PURERB-pure-ruby-runtime.md) gains its first active plan and
  concrete research output
- `docs/gc-replacement-requirements.md` gives the next implementation plan a concrete
  spec to build against, rather than designing a Ruby GC in a vacuum
- Answers the "why is GC disabled?" question that the README leaves unexplained
- The allocation volume measurement reveals whether GC matters at all in the short term
  (if compilations use <10 MB, the current leak-and-exit approach may be acceptable until
  the compiler is used for long-running programs)

**Downstream (PURERB):**
- The requirements document is the spec for implementing a Ruby GC in [lib/core/](../../../lib/core/)
- The API surface documentation gives the implementation plan exact function signatures to replicate
- The circular dependency analysis determines whether the Ruby GC can be written in standard Ruby
  or requires low-level workarounds
- The allocation taxonomy tells the Ruby GC what object types it must handle (and which it doesn't
  need to scan — e.g., leaf allocations for string buffers don't contain pointers)

**Downstream (SELFHOST, COMPLANG):**
- Re-enabling the C GC (if feasible) would fix the memory leak in all compiled programs,
  making the compiler viable for programs that process large inputs
- The tagged-pointer analysis informs any future work on object tagging (e.g., expanding
  fixnum range, adding nan-boxing)

## Proposed Approach

**Step 1: Re-enable GC and observe** — In [lib/core/base.rb](../../../lib/core/base.rb),
uncomment lines 22 and 53 (the `tgc_start` and `tgc_stop` calls). Run `make selftest` and
`make selftest-c`. Record whether they pass or crash, and capture the crash/error output.

**Step 2: Investigate breakage** — If selftest crashes, use `make valgrind` to get a
stack trace. Look for common conservative GC failure modes:
- Fixnums (odd-valued, since bit 0 = 1) being treated as pointers
- Stack scanning including callee-saved registers that contain fixnums
- `__roots_start`/`__roots_end` bounds being wrong
Record the exact failure mode. Revert the uncomment if it breaks selftest.

**Step 3: Document tgc.c API** — Read [tgc.c](../../../tgc.c) and list all exported
functions with their signatures, semantics, and internal implementation approach (conservative
mark-and-sweep, hash table of tracked pointers, uses `setjmp` to flush registers onto stack).

**Step 4: Trace allocation call sites** — Search [lib/core/base.rb](../../../lib/core/base.rb)
and generated assembly output (`out/selftest.s`) for all allocation patterns. Identify what
each allocates (object slots, vtable, array body, string bytes, etc.) and whether it's a
leaf allocation (no pointers inside) vs. a node allocation (contains pointers).

**Step 5: Measure with Valgrind** — Run `make valgrind` (which runs selftest under Valgrind)
and capture `--tool=massif` or `--leak-check=full` output to measure total allocation volume
and allocation count. If `make valgrind` uses memcheck, look for "total heap usage" in the
output.

**Step 6: Analyze tagged-pointer interaction** — Review how fixnums are stored (likely
`(n << 1) | 1` or similar — confirm by reading [lib/core/integer_base.rb](../../../lib/core/integer_base.rb)
or [lib/core/integer.rb](../../../lib/core/integer.rb)). Calculate what fraction of fixnum
values in the range 0..255 would pass the tgc heap range check (`gc.minptr .. gc.maxptr`)
and look like valid pointers.

**Step 7: Write requirements document** — Synthesize all findings into
`docs/gc-replacement-requirements.md` following the structure described in the Scope section.
Include at minimum: current state, API surface, allocation taxonomy, allocation volume,
tagged-pointer interaction, and 2+ replacement approaches with trade-offs.

## Acceptance Criteria

- [ ] [lib/core/base.rb](../../../lib/core/base.rb) `tgc_start` and `tgc_stop` calls are
  un-commented, `make selftest` is run, and the result (PASS or CRASH + crash reason) is
  documented in the plan log. Whether these lines end up commented-out or not in the final
  commit depends on the result.

- [ ] `docs/gc-replacement-requirements.md` exists and contains:
  - A "Current State" section explaining why GC is disabled and what breaks if re-enabled
    (with evidence from the selftest run in criterion 1)
  - A "tgc.c API Surface" section listing all exported functions with their signatures
    and semantics (minimum: `tgc_start`, `tgc_stop`, `tgc_add`, `tgc_realloc`)
  - An "Allocation Taxonomy" section classifying what compiled programs allocate (object
    slots, vtable, array body, string bytes, closure env, etc.)
  - An "Allocation Volume" section with at minimum a total byte count from Valgrind or
    an `strace`-based estimate during selftest compilation
  - A "Tagged-Pointer Interaction" section explaining how fixnums affect conservative
    GC scanning and whether this is the cause of GC disablement
  - A "Replacement Approaches" section with at least 2 concrete strategies and trade-offs
  - A "Recommendation" section identifying which approach to implement first

- [ ] The document's "Allocation Taxonomy" section correctly identifies whether string
  buffer allocations are leaf allocations (no internal pointers) vs. node allocations —
  this can be verified by reading `__alloc_leaf` vs. `__alloc_mem` usage in
  [lib/core/base.rb](../../../lib/core/base.rb) and [lib/core/string.rb](../../../lib/core/string.rb)

- [ ] `make selftest` passes in the final state of the working tree (either with GC
  re-enabled and working, or reverted to the disabled state with the reason documented)

---
*Status: PROPOSAL - Awaiting approval*
