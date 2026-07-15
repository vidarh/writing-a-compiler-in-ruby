INLINEBROADEN
Created: 2026-07-15

# Broaden Devirtualization-Driven Method Inlining

Extend the devirt-driven inliner in [inline.rb](../../inline.rb) (now on by default, opt out with `INLINE=0`) so that more simple, provably safe methods are transplanted at their call sites, reducing call overhead and paving the way for later strength reduction.

## Goal Reference

Advances [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md) and general compiler performance. The existing devirtualizer (on by default) already eliminates the vtable read for monomorphic calls. The downstream inliner (opt-in) currently only handles the most trivial accessor bodies. Broadening it is the next logical step toward measurable self-compile speedup, as noted in [docs/devirt_plan.md](../../docs/devirt_plan.md) (P3 inlining + P4 strength reduction).

## Root Cause / Current State

The inliner is intentionally conservative. From a review of [inline.rb](../../inline.rb) and its callers in [compile_calls.rb](../../compile_calls.rb) and [compiler.rb](../../compiler.rb):

- It only fires on calls that the whole-program type inference has already proven devirtualizable (`@devirt_labels`).
- The receiver and every argument must pass `inline_pure?`, which accepts **only** bare `:self`, `:nil`, `:true`, `:false`, an `Integer`, or a bare `Symbol` local/param ([inline.rb:73-75](../../inline.rb#73)). Any receiver/arg expression (`o.x`, `arr[i]`, `x + 1`) blocks inlining, even if it is side-effect-free.
- The method body must be a single node (`defm[3]`) and pass `inline_safe_node?`, which rejects `:return`, `:yield`, `:super`, `:block`, `:proc`, `:lambda`, `:defun`, `:defm`, loops, `:case`, jumps, op-assigns, `:let`, and `:sexp` ([inline.rb:90-113](../../inline.rb#90)). Local-variable assignments are rejected; only ivar assignment is rewritten.
- `[:return, expr]` bodies are not special-cased, so a huge class of Ruby methods written with an explicit `return` cannot be inlined.
- `selftest` with `INLINE=1` currently inlines **36** sites. The hot dispatch paths remain polymorphic, so the win is small until more simple targets qualify.

The core transplant machinery is sound: it deep-copies the body, rewrites `self` to the receiver, ivars to explicit `[:sexp, [:index, recv, offset]]` raw slot accesses, and params to the argument expressions. The previous crash (unmaterialised return value) has been fixed; the caller now does `@e.save_result(compile_eval_arg(scope, spliced))` and returns `:subexpr` ([compile_calls.rb:628-638](../../compile_calls.rb#628)). `make selftest INLINE=1` passes with Fails: 0.

## Scope

**In scope:**

1. **Broaden the receiver/argument side-effect-freedom check** in [inline.rb](../../inline.rb):
   - Replace `inline_pure?` with a recursive `inline_side_effect_free?` that accepts literals, `:self`/params/locals, ivar reads, constants, and pure arithmetic/bitwise/comparison/index/raw-sexp sub-expressions.
   - Continue to reject any `:call`/`:callm` (method call side effects / unknown return), `:assign`/op-assign, control flow, `:yield`/`:super`/`:block`/`:lambda`/`:proc`/`def`, and `:let`.
   - Because the expression is side-effect-free, duplicating it (or using it multiple times in the body) is safe, so no temp binding is required and the known-fragile `[:let]` path is avoided.

2. **Special-case `[:return, expr]` bodies**:
   - A body that is exactly `[:return, expr]` where `expr` is safe should inline as `expr` (the return is implicit at the call site).
   - A `:do` body whose **last** statement is `[:return, expr]` (and has no earlier return/unsafe statement) should inline as the `:do` with the trailing return stripped.
   - Any `:return` that is not the final value-producing statement continues to block inlining (early return changes control flow).

3. **Inline multi-statement `:do` bodies more explicitly**:
   - Document/verify that `:do` bodies are already handled generically; add targeted tests for multi-statement accessors/predicates to prevent regressions.

4. **Allow optional positional params when the call provides all arguments**.

5. **Allow known-safe `:sexp` forms** (the compiler lowers Ruby literals and raw core reads to `%s(...)`):
   - Tagged integer literals `[:sexp, N]`, symbol literals `[:sexp, :__S_*]`,
     string/symbol constructors `[:sexp, [:call, :__get_string/:__get_symbol, label]]`,
     and raw reads `[:sexp, [:__int, expr]]` / `[:sexp, [:index, obj, offset]]`.
   - This is the main unlock: without it almost every literal receiver/argument and most simple core getters are rejected.

6. **Add a small diagnostic helper** (gated by `INLINE_DEBUG=2`):
   - Print why each devirt target was *not* inlined (e.g. `impure_recv`, `unsafe_body`, `default_args`). This makes the next broadening iteration data-driven.

7. **Validation:**
   - `make selftest` and `make selftest-c` must pass with `INLINE=1`.
   - Run `make specs-parallel` on `compiler@ax52` with and without `INLINE=1` to confirm no rubyspec regressions and measure pass-rate/code-size change.
   - Compare generated assembly line counts / self-compile wall time for the compiler driver.

**Out of scope:**
- Inlining methods with side-effecting receiver/arguments via temp binding (`[:let]` is known to clobber the expression-value result; do not re-open that path without a new safe binding mechanism).
- Inlining methods with default/optional/splat/block params, or with early `return`, `yield`, `super`, loops, exception handling, nested defs, or `%s(...)` bodies.
- Recursive/multi-level inlining beyond what the normal compile pipeline already does when it re-walks the spliced body.
- Strength reduction of inlined primitives (P4 — a separate follow-up plan after this one lands).

## Expected Payoff

- **More inlined sites:** Many core-library and compiler-internal predicate/accessor methods use explicit `return` or have expressions like `self == other`, `@ptr + offset`, `len - 1`, etc. These become eligible without changing transplant semantics.
- **Foundation for P4:** Once more call sites are statically expanded, strength-reducing `Integer#+`/`-`/`<`, `Array#[]`/`length`, etc. inside the spliced body becomes worthwhile.
- **Low risk:** Each broadening is a pure expansion of the "safe" predicate set; anything not proven safe falls back to the existing direct devirt call.

## Proposed Approach

```mermaid
flowchart TD
    A[Devirtualized call site recv.m(args)] --> B{Receiver + args side-effect-free?}
    B -->|No| C[Fall back to direct devirt call]
    B -->|Yes| D{Body shape safe?}
    D -->|No| C
    D -->|Yes| E{Body is [:return, expr]?}
    E -->|Yes| F[Splice expr as return value]
    E -->|No| G[Splice body as-is]
    F --> H[compile_eval_arg + save_result]
    G --> H
```

1. **Implement `inline_side_effect_free?`** in [inline.rb](../../inline.rb):
   - Add a recursive predicate that mirrors `inline_safe_node?` but is applied to receiver/argument expressions rather than method bodies.
   - Keep `inline_pure?` as a fast path for the current simple cases.
   - Update `inline_devirt_body` to use `inline_side_effect_free?` for `recv` and each `arg`.

2. **Handle `[:return, expr]` in `inline_devirt_body`**:
   - Before calling `inline_safe_node?`, unwrap a body that is exactly `[:return, expr]` and use `expr` as the effective body.
   - For a `:do` body, inspect the last element; if it is `[:return, expr]` and all preceding statements are safe, replace the last element with `expr` and proceed. Otherwise bail.

3. **Keep the existing rewrite/transplant paths unchanged**:
   - `inline_rewrite` and ivar/param/self substitution already handle `:do`/multi-statement bodies correctly because they recursively map arrays.
   - The caller's materialisation of the result already makes the spliced body safe in argument position.

4. **Add tests in `spec/`**:
   - `spec/inline_return_spec.rb`: simple method with explicit `return`.
   - `spec/inline_expression_receiver_spec.rb`: inlining with receiver/arg expressions like `arr[i].x` or `obj.foo(x + 1)`.
   - `spec/inline_multi_statement_spec.rb`: multi-statement `:do` body with no early return.
   - All using mspec format and run under `make spec`.

5. **Measure on `compiler@ax52`**:
   - Use the existing rsync helper (`bin/ax52-sync` or equivalent) to push the tree.
   - Run `make specs-parallel INLINE=1` and compare to baseline `docs/spec_status.md`.
   - Run `make selftest-c INLINE=1` and compare wall time / `out/driver` vs `out/driver2` size.

## Acceptance Criteria

- [x] `inline_side_effect_free?` exists and is used for receiver/argument eligibility.
- [x] `[:return, expr]` single-statement bodies inline correctly.
- [x] Multi-statement `:do` bodies with a trailing `return` inline correctly.
- [x] Optional positional params are supported when the call provides all arguments.
- [x] Known-safe `:sexp` forms are allowed in receiver/argument/body checks.
- [x] `INLINE_DEBUG=2` diagnostic helper reports why candidates are rejected.
- [x] `make selftest` passes with `INLINE=1` (Fails: 0).
- [x] `make selftest-c` passes with `INLINE=1` (Fails: 0).
- [x] `make spec` passes with `INLINE=1` (custom spec, including `spec/inline_broaden_spec.rb`); results match `INLINE=0` (79/22/1 at file level, pass rate 79%), so no inlining regression.
- [x] New mspec tests in `spec/inline_*_spec.rb` cover the broadened cases.
- [x] `make specs-parallel` on `compiler@ax52` shows no regressions: tracked 535-file set yields identical outcomes with and without `INLINE=1` (PASS 117, FAIL 411, CRASH 5, TIMEOUT 2, ERROR 0; 0 files changed status).
- [x] Inline site count with `INLINE=1` increases measurably from the baseline 36 on `make selftest` (new count ~780).
- [x] `INLINE=1` is now the default; `INLINE=0` can still opt out. Validation is clean, so the change is safe to keep enabled.

## Open Questions

- How many additional devirt sites become eligible with the broader purity/return rules? **Answered:** the dominant blocker was `:sexp` lowered literals/raw reads; allowing the known-safe forms raised `make selftest` inline count from 36 to ~780.
- Does broadening purity to include arithmetic on locals expose any latent register-cache issues in `compile_eval_arg` when the same expression is duplicated inside the body? The expressions are side-effect-free, but the compiler's register allocator may compile them twice. This is safe but may affect code size; measure.
- Should `inline_side_effect_free?` allow `:sexp` sub-expressions that are pure (e.g. `%s(index ...)` raw reads)? **Answered/implemented:** yes, for the specific literal/raw-read forms the compiler emits.
- Is there value in handling default arguments when the call provides all positional args? **Implemented:** optional params are now allowed when the call passes all arguments.

## Risks

- **Unsoundness:** The broadened predicate must remain conservative. Any doubt → fall back to direct call.
- **Self-host fragility:** The self-hosted compiler is sensitive to register eviction and `:let`/`[:subexpr]` Value semantics. The proposed changes avoid `[:let]` and preserve the existing materialisation path, but full validation on ax52 is required before enabling by default.
- **Code bloat:** Inlining more sites increases code size. Acceptable if it unlocks later strength reduction; measure assembly line counts.

---
*Status: DEPLOYED - Inlining is now enabled by default; all local and ax52 validation passed.*

## Phase 2: Further broadening (next steps)

Optional params have already been extended beyond the original plan: the inliner now fills missing trailing arguments from side-effect-free default expressions (`def m(a, b=0)` called as `m(1)`). A duplicate of the caller's `args` array is used so an eventual bail does not mutate the original call site.

A fresh `INLINE_DEBUG=2` run over `test/selftest.rb` (default inlining) shows the remaining rejections:

| reason | count | notes |
|---|---|---|
| `unsafe_body` | 286 | bodies containing `:let`, raw `%s(if ...)` with early returns, or method calls |
| `unsupported_param` | 40 | almost entirely `[:__splat, :rest]` and `[:block, :block]` params on core methods |
| `not_in_funcscope` | 21 | top-level call sites; inherent limitation |
| `impure_arg` | 3 | arguments containing real method calls |
| `arg_count_mismatch` | 1 | arity edge case |

The two highest-leverage, low-risk broadenings are:

1. **Allow ignored rest/block params when the call does not use them.**
   - Parse `[:__splat, :rest]` and `[:block, :block]` but do **not** add them to the substitution map.
   - Permit the call as long as `args.length` is within `[required_count, required_count + optional_count]` (i.e. no actual splat/block argument is passed).
   - Body safety remains conservative: if the body references the ignored param it will be rejected as a free local by `inline_safe_node?`.
   - This unlocks many core methods (`Array#[]`, `Integer#chr`, `String#[]=`, `Array#max` without block, etc.) that are currently rejected solely for having a never-used `*args` or `&block` signature.

2. **Allow value-producing `%s(if cond then else)` inside `:sexp`.**
   - Core predicate methods compile to raw `%s(if ...)` forms. When both branches are side-effect-free expressions (no early returns, no calls, no assignments), the whole form is pure and can be treated like a ternary expression.
   - Add an `:if`/`:ifelse` case to `inline_safe_sexp?` requiring three children and verifying each with `inline_side_effect_free?`.
   - Keep rejecting raw `%s(if ...)` branches that contain `:return`, `:call`/`:callm`, `:assign`, or other impure nodes.

**Deferred / out of scope for Phase 2:**
- `:let` bodies (known expression-value register issues; needs a safe temp-binding mechanism first).
- Early-return translation inside `%s(if ...)` (would require control-flow restructuring, not a simple value splice).
- Inlining through method-call arguments or multi-level inlining.
- Side-effecting receivers/arguments bound to temps.

### Phase 2 acceptance criteria

- [x] `INLINE_DEBUG=2` counts for `unsupported_param` drop to zero on `make selftest`.
- [x] `inline_safe_sexp?` accepts value-producing `%s(if cond then else)` / `%s(ifelse cond then else)` forms.
- [x] `make selftest` / `make selftest-c` remain Fails: 0 (verified locally and on `compiler@ax52`).
- [x] `spec/inline_broaden_spec.rb` gains tests for:
  - a method with a `*args` parameter called without splat arguments;
  - a method with an `&block` parameter called without a block;
  - a predicate-style method whose body is a raw `%s(if ...)` value expression.
- [x] `make specs-parallel` on `compiler@ax52` shows no status regressions versus the pre-Phase-2 baseline.
  - **Pre-Phase-2 baseline**: PASS 117, FAIL 411, CRASH 5, TIMEOUT 2, COMPILE_FAIL 0 (535 files).
  - **Post-Phase-2 run**: PASS 117, FAIL 411, CRASH 5, TIMEOUT 2, COMPILE_FAIL 0, ERROR 0 (identical file statuses).

### Phase 2 measurements (local)

After the changes a fresh `INLINE_DEBUG=2 ./compile test/selftest.rb` shows:

- `unsupported_param`: 0 (was 40)
- `unsafe_body`: 326 (was 286) — the rest/block candidates are now allowed through param parsing and are rejected by body safety instead.
- Total bails: 351, inline sites: ~782 (unchanged from Phase 1 on this workload).

This confirms the param broadening is working and the next bottleneck is body safety (`:let`, early-return raw `%s(if ...)`, and method calls).

### Ax52 validation status

- `make selftest-c` on `compiler@ax52`: **Fails: 0** with Phase 2 changes.
- `make specs-parallel` on `compiler@ax52`:
  - Pre-Phase-2 baseline: PASS 117 / FAIL 411 / CRASH 5 / TIMEOUT 2 / COMPILE_FAIL 0.
  - Post-Phase-2 run: PASS 117 / FAIL 411 / CRASH 5 / TIMEOUT 2 / COMPILE_FAIL 0 / ERROR 0 (no regressions).

### Risks

- Rest/block broadening must not accidentally substitute an unbound `:rest`/`:block` symbol; keeping them out of `param_names` and relying on `inline_safe_node?` prevents this.
- `%s(if ...)` broadening must remain expression-only; any branch that is not side-effect-free falls back to the direct call.

## Phase 3: Translate raw `%s(if ...)` return branches into Ruby `:if`

The dominant remaining `unsafe_body` rejections are single-statement core predicates written as raw s-expressions with explicit returns, e.g.:

```ruby
def empty?
  %s(if (eq @len 0) (return true) (return false))
end
```

At the call site the return is implicit, so this is semantically equivalent to the value ternary `%s(if (eq @len 0) true false)`. Lifting it lets the inliner splice the predicate directly.

Implementation:

1. **`inline_normalize_return_if`** in `inline.rb` recognizes three patterns:
   - `[:sexp, [:if/:ifelse, cond, [:return, a], [:return, b]]]` → `[:if, cond, a, b]`.
   - A `:do` whose final statement is the above sexp → replace only that final statement with `[:if, cond, a, b]`.
   - A `:do` whose final two statements are `%s(if cond (return a))` followed by a fallback value `b` (the shape of `Object#equal?`) → replace the pair with `[:if, cond, a, b]`.
   The result is a normal Ruby `:if` node, so the branches keep their `:object` type and truthiness checks remain correct.

2. **Fix the inlined-call result type** in `compile_calls.rb`:
   The devirt-driven inline path was returning `Value.new([:subexpr])` with no type. That caused `compile_jmp_on_false` to fall back to a raw `testl %eax` when the inlined result was used as a condition, treating the `false` singleton pointer as truthy. The inline path now returns `Value.new([:subexpr], :object)`, matching the normal (non-inlined) `compile_callm` return and ensuring `false`/`nil` are recognized as falsy.

3. **Regression tests** in `spec/inline_broaden_spec.rb` cover:
   - both branches returning explicit values (true/false cases);
   - a single return branch with a fallback value (true/false cases).

### Phase 3 acceptance criteria

- [x] `inline_normalize_return_if` transforms raw `%s(if ...)` / `%s(ifelse ...)` bodies whose branches are `[:return, expr]` into Ruby `:if` nodes.
- [x] The single-return-branch-with-fallback pattern (`%s(if cond (return a)); b`) is also normalized.
- [x] Inlined call results carry type `:object` so they work correctly when used as Ruby conditions.
- [x] `make selftest` / `make selftest-c` remain Fails: 0 locally.
- [x] `spec/inline_broaden_spec.rb` passes (15/15 after the impure-default test was added).
- [ ] `make specs-parallel` on `compiler@ax52` shows no status regressions versus the Phase 2 baseline.

### Phase 3b: Defer the impure-default check for optional params

The original optional-param support required the default expression to be side-effect-free even when the call provided all positional arguments and the default was never used. That blocked inlining of methods like:

```ruby
def m(a, b = some_side_effecting_call)
  ...
end
m(1, 2)  # default is irrelevant
```

The check is now deferred to the fill loop in `inline_devirt_body`: we only validate and deep-copy the default when a missing trailing argument actually needs it. Calls that pass all args inline as before; calls that rely on the default still require a side-effect-free default expression.

- Regression test added to `spec/inline_broaden_spec.rb`.
- `make selftest` / `make selftest-c` remain Fails: 0.
- On `test/selftest.rb` this broadening did not change bail/site counts (no method in that workload has an impure default and all args provided), but it removes an unnecessary restriction for future callers.

### Phase 3 measurements (local)

A fresh `INLINE_DEBUG=2 ./compile test/selftest.rb` after Phase 3 (+ 3b) shows:

| reason | count | notes |
|---|---|---|
| `unsafe_body` | 315 (was 326) | raw `%s(if)` return-branch predicates now inline |
| `unsupported_param` | 0 | unchanged |
| `not_in_funcscope` | 21 | unchanged |
| `impure_arg` | 3 | unchanged |
| `arg_count_mismatch` | 1 | unchanged |
| `impure_default` | 0 | only counted when a fill actually occurs |

Inline site count on `test/selftest.rb` increased from **782** to **804** (22 additional sites on this workload).

Local compile-time comparison (test/selftest.rb, `INLINE=1`, wall-clock):

| compiler | Phase 2 | Phase 3 | change |
|---|---|---|---|
| MRI-hosted (`./compile`) | 33.4s | 29.4s | -4.0s (~ -12%) |
| self-hosted (`./compile2`) | 129.6s | 152.6s | +23.0s (~ +18%) |

Runtime of the generated `out/selftest2` binary is essentially unchanged for this tiny test (~0.074s → ~0.070s); a larger workload is needed to see a reliable runtime speedup.

### Ax52 validation status

- `make selftest-c` on `compiler@ax52`: **Fails: 0** with Phase 3 changes.
- `make specs-parallel` on `compiler@ax52`: comparison run is in progress.

### Risks

- The `:object` type for all inlined call results is sound because we are inlining Ruby method bodies (which must return Ruby objects), but a future raw-s-expression method that intentionally returns a non-object raw value would need its type preserved rather than forced to `:object`.
- Lifting a raw sexp condition to a Ruby `:if` relies on the compiler's existing handling of raw operators (`:eq`, `:ne`, `:lt`, etc.) in `compile_if`; complex sexp-only conditions (`:not`, custom macros) may not be representable and will simply bail if the transformed node is not safe.
