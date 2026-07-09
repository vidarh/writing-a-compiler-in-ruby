# Burndown triage — near-passing specs

Running log of near-green specs (F ≤ ~2) assessed for "what's the one fix to flip it
green", so passes go for **easy wins first** and steer clear of the known-hard ones until
those are exhausted. Update as specs are assessed/fixed. Source: `docs/spec_status.md`.

Legend: **EASY** (localized, low-risk) · **FEATURE** (needs a missing feature) ·
**DEEP** (deep/risky subsystem) · **BLOCKED** (depends on unsupported thing).

## Update (2026-07-09) — a fresh WHOLE-SPEC-FAIL round mined many easy wins

The 2026-06-26 "no easy wins left" finding below was for the F ≤ 2 near-passing specs in a few
categories. Widening to **P:0 whole-spec-FAIL specs** (missing methods) + **core-iteration
correctness** across core/array, hash, nil, enumerable, set, comparable produced a large batch of
flips this session: Array#each (size-reread + return self, 3/10→11/0), all?/any?/none?, concat,
replace, Enumerable#compact/chain/filter/collect_concat/reverse_each, NilClass#to_r/#to_c,
Hash#to_hash/#values_at, Set#classify, Comparable#clamp, type-strict eql? across Integer/Rational/
Array/Struct, and a cluster of TypeError-validation fixes (Hash#fetch/dig, Object#instance_of?,
Hash#flatten). PASS 520→545 over the session.

**That accessible vein is now (again) largely exhausted.** The remaining near-passing surface is
dominated by: the should_receive-on-existing-method mock limitation ([[compiler_stub_override_blocks_specs]]
— blocks most core/numeric + core/complex), the bignum heap-multiply bug, `ruby_version_is` running
both version branches, and the deep codegen tails. Next real gains need a FEATURE (stub-override /
dynamic-ivar reflection, or bignum), not one-line adds.

## Key finding (2026-06-26)

Across the F ≤ 2 specs in **language + core/integer + core/string + core/regexp**, there are
currently **no localized easy wins left** — every near-passing spec assessed is blocked by a
large missing feature/subsystem, not a small bug. To make further progress here, pick a
*cluster* (below) or widen `make specs-parallel` to other categories (core/array, core/hash,
…) to find fresh easy wins.

## Assessed (F ≤ 2)

| spec | F | verdict | root cause |
|---|---|---|---|
| core/integer/gcd | 2 | DEEP | Euclidean algo correct; bug is **bignum multiplication** (`9999**25 * 9999**25 ≠ 9999**50`). `Integer#__multiply_heap_by_heap` (integer.rb:893) carries incompletely: when a partial product's carry exceeds one limb it adds to `result_limbs[i+j+1]` unnormalized (lines ~962-970), corrupting the slot read next iteration. Root constraint: limb_base 2^30 == fixnum range, no headroom for column sums → needs smaller limb base or raw-64-bit accumulation. Substantial. |
| core/integer/lcm | 2 | DEEP | uses gcd → same bignum-multiply bug. |
| core/integer/lt | 1 | FEATURE | "CoerceError expected, none raised" → **coerce protocol** missing in comparisons. |
| core/integer/lte | 2 | FEATURE | coerce protocol + comparison-with-Float. |
| core/integer/case_compare | 2 | BLOCKED | `9 === 9.0` (**Float**) + bignum equality. |
| core/integer/equal_value | 2 | BLOCKED | same shared examples: Float + bignum. |
| core/integer/ceildiv | 2 | BLOCKED | divisors `1.2` (Float), `6/5r` (Rational), `10**99` (bignum) → become 0. |
| core/regexp/options | 1 | FEATURE | "TypeError expected, none raised" (arg type-checking). |
| core/regexp/try_convert | 1 | FEATURE | TypeError on bad arg. |
| core/regexp/source | 2 | BLOCKED | metachar escaping (`\@`) + **encoding** objects. |
| core/string/eql | 2 | BLOCKED | **encoding** (`force_encoding`, utf-32le); value/subclass eql? already work. |
| core/string/allocate | 2 | BLOCKED | **encoding** + length-of-allocated. |
| core/string/uplus | 2 | BLOCKED | frozen-string copy semantics + `should_not.frozen?` shim arity + `ruby_exe`. |
| language/comment | 1 | BLOCKED | uses runtime `eval` (out of scope for AOT). |

## Clusters (one feature → several specs)

- **coerce protocol** in Integer comparison/arithmetic → lt, lte, and likely gt/ge/<=>.
  Most self-contained of the clusters. Good next candidate if staying in these categories.
- **bignum** correctness (modulo, `**`) → gcd, lcm, and many integer specs.
- **Float** support → case_compare, equal_value, lte, ceildiv, … (large).
- **encoding** (`force_encoding`, transcoding, Encoding objects) → many string/regexp specs.
- **eval / ruby_exe** → blocks specs needing runtime eval or subprocess; out of scope.

## Fixed
- **core/symbol/case_compare** → GREEN. `Class#===` was missing (fell back to Object#=== = `==`),
  so `Klass === obj` was always false and every `case/when ClassName` mis-dispatched. Added
  `Class#===` = `other.is_a?(self)` (lib/core/class_ext.rb). Correctness win beyond the one
  green flip: `case/when` with class patterns now works.
- **core/array crash cluster (~39 specs)** → fixed. The shared array fixture
  (`fixtures/classes.rb`) crashed at load on `CHI_SQUARED_CRITICAL_VALUES`, a Float array
  containing `20.090` etc. Root cause: the float tokenizer parsed the fractional part with
  Int.expect, applying leading-zero=octal rules, so `.090` tried to parse `090` as octal (9
  invalid) → bad data → segfault. Fixed by reading fractional digits as a raw decimal
  string (tokens.rb). Broad set: CRASH 204→165, tests 879→942.
