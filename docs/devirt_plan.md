# Devirtualization via vtable-generation type inference — plan

Supersedes the muddled freeze/typed-literal material in type_inference_design.md (those attempts were
unsound — they assumed a fixed method version and reasoned about locals/heuristics). This is the correct
model, grounded in the compiler's actual dispatch machinery. Goal: devirtualize -> inline -> strength-
reduce (e.g. Integer#+ on small values -> `addl`) to speed up the compiler's SELF-compilation.

## The trusted contract (verified by code review, 2026-07-13/14)

Dispatch is O(1) with NO chain walk: `recv.m` = load recv's class pointer (`recv[0]`) -> read the fixed
global slot `offset(m)` -> call it. recv's class pointer is either `.class` or the object's **eigenclass**
(if it has singleton methods). The whole MRO (eigenclass, prepends, class, includes, supers) is FLATTENED
into that one vtable.

`__set_vtable(vtable, off, ptr)` (lib/core/class.rb:63) is the single mutator and it **propagates down**
the subclass chain (slot 4 = first subclass, slot 5 = next sibling; recurses into children that haven't
overridden). `def` (runtime, during class-body exec), `include`, and `alias` all go through it.

**We TRUST this contract rather than analyze its implementation.** Corollary for the compiler: a vtable
slot `(C, m)` can change ONLY via `__set_vtable(C', offset(m), _)` for C' = C or an ancestor of C. (The
`Module#define_method` -> global `$__dm` side-table path and `prepend`-as-no-op are real bugs but do NOT
affect the compiler's own dispatch, so fixing them is deferred; the compiler's method definitions all flow
through `__set_vtable`/static `def`.)

## Abstract domain

An expression's TYPE = a set of `(V, G)` where V is a vtable identity and G a generation-range:
- **V (points-to on the class pointer):** a named class's vtable (:Array, :Integer, a compiler class),
  or FRESH#n (a distinct `Class.new` allocation site -- provably NOT a named class), or an EIGEN marker
  (the object may have a singleton class -> unknown per-object vtable), or TOP (any).
- **G (generation-range):** the set of `__set_vtable` events on V (or an ancestor, propagated) that could
  have executed at the point the type is observed. Bounded by control flow up to the expression.

Sound "may" analysis: anything unhandled widens to TOP-V / all-G. Wrong here = miscompiled call.

## The two analyses

1. **Points-to for class pointers (whole-program).** Rides the existing scope chain (`get_arg` resolves
   names) and `Value.type` (already carries a per-value type tag). Sources: literals -> their class;
   `C.new` -> instance of C; inlined `Class.new` (`__new_class_object` block) -> FRESH#n; `def_target`/
   `define_singleton_method`/`class << x` -> EIGEN. Flow: assignment/phi joins, and interprocedural param
   types (union over call sites) + return types (union of a method's returns) to a fixpoint. Must type BOTH
   call receivers AND the receiver of every `__set_vtable`-causing op (def in a block, include, alias,
   define_method) so we know which vtables each modification reaches.
2. **Generation / slot-stability.** For a slot `(C, m)`, collect the `__set_vtable(C', offset(m), _)`
   events where C' is C or an ancestor (points-to on C' includes C or an ancestor). A call `recv.m` at a
   program point observes a stable slot iff NONE of those events can execute in the receiver's generation-
   range (i.e. after recv's `(V,G)` is pinned, up to the call). For the compiler this is dominated by the
   init phase: nearly all `__set_vtable`s run while class bodies execute; the compiler's main work runs
   after and issues none against the classes it calls -> those slots are stable there.

## Devirtualization test (slot-invariance)

At `recv.m` with off = offset(m): if recv's type is a set of `(V,G)` such that (a) every V is a concrete
named-class vtable with NO EIGEN/TOP possibility, and (b) `slot[off]` holds the SAME function across all
those V and their G-ranges (from analysis 2), then the target is that single function -> emit a direct
`call __method_<C>_<m>` instead of the vtable read. Monomorphic single-`(V,G)` is the first case.

## Downstream (the point of it)

- **Inline** the now-statically-known small targets at the call site (the compiler already installs
  trampolines, so the machinery to reason about a specific function body exists).
- **Strength-reduce** inlined primitives: `Integer#+`/`-`/`<` etc. on operands both proven fixnum ->
  raw `addl`/`subl`/`cmpl` + overflow->Bignum slow path; `Array#[]`/`length` on a proven Array ->
  direct ivar/index. This is where measurable self-compile speedup comes from (dispatch read-skipping
  alone measured neutral).

## Phasing (each phase: gate + FULL sweep before commit; sound-by-construction)

- **P1 — generation/stability analysis + points-to on LITERAL receivers.** Smallest sound devirt; proves
  the pipeline end-to-end. (Payoff small -- literals are cold -- but validates correctness + the direct-
  call emission against a real sweep.)
- **P2 — points-to flow inference for VARIABLE/PARAM receivers** (the hot ones): the whole-program
  fixpoint. This is the bulk and where real receivers get typed.
- **P3 — inlining** of statically-resolved small methods.
- **P4 — strength reduction** on inlined fixnum/array primitives.

## Open questions to resolve while building P1 (don't guess -- verify in code)
- Exact eigenclass creation points and whether `recv[0]` observably becomes the eigenclass (so EIGEN is
  detectable / excludable).
- How offsets are assigned for names only ever `define_method`'d (no static `def`) -- do they get a slot?
- Whether any compiler/lib-core `__set_vtable` runs AFTER init against a class the compiler calls (would
  shrink the stable set); measure via an instrumented build.
