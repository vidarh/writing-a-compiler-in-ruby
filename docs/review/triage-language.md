# Triage: rubyspec/language/ failures

Date: 2026-07-04. Source: `docs/spec_status.jsonl` (68 language/ files with outcome
FAIL, **1890 failing tests** total) plus fresh runs of 20 spec files (the 15
highest failed-counts + 5 mid/low representatives). Raw outputs: `/tmp/triage-lang/*.out`.

Failed-count per file comes from the jsonl; per-cluster counts inside a file are
estimated from failure-signature counts in the fresh runs (assertion-level, so
slightly above test-level in places).

## Headline

The slice is NOT dominated by one hard problem. Roughly:

- ~350 tests hang off **three trivial/easy fixes** (rubyspec_helper matcher gaps,
  `module_function` being a no-op stub, `Warning` constant missing).
- ~400 tests are **medium, well-localized** compiler/runtime work in five areas
  (`defined?`, `$!`, regexp match globals, qualified-constant assignment,
  block-param destructuring).
- ~85 are one coherent **kwargs** workstream.
- ~310 are **hard/project-scale** (pattern matching 222, regexp engine ~94).
- ~160 are **wontfix-ish** for an AOT compiler (SyntaxError-from-eval tests,
  magic comments, encodings).
- The rest is a diffuse "strictness" long tail (missing TypeError/ArgumentError/
  FrozenError/NoMethodError raises) worth ~100+ tests incrementally.

---

## Clusters

### C1. rubyspec_helper gaps — matchers and stubs (TRIVIAL)
**Signatures:**
- `should_not ComplainMatcher` — `ComplainMatcher#match?` always returns `true`
  (rubyspec_helper.rb:717), so every `should_not complain` fails. ~55 call sites
  across 13 language files (block 11, method 14, hash 8, variables 5, predefined 4, ...).
- `undefined method 'have_method' / 'have_instance_method' / 'have_constant' /
  'be_ancestor_of'` — matchers simply missing from the helper
  (singleton_class alone: 23 of its 63 failures).
- `uninitialized constant Warning` — no `Warning` module; a `before :each` hook
  using `Warning[:experimental]` fails for **97 of pattern_matching's 222** tests
  (plus 2 in method_spec). NOTE: stubbing Warning mostly converts these into
  *real* pattern-matching failures, not passes — but it un-gates the file and
  passes the handful of "does not warn" tests.
- `undefined method 'suppress_keyword_warning'` (block 2), `ruby_cmd` (predefined 1).

**Affected/payoff:** direct passes ≈ 70–90 (block ~12, method ~10, singleton_class ~23,
variables ~5, hash ~5, metaclass/def/optional_assignments a few each) + un-gates ~100.
**Complexity:** trivial — all in `rubyspec_helper.rb`, no compiler changes.
**Fix:** make ComplainMatcher record a skip and satisfy both `should`/`should_not`;
add the four reflection matchers (trivial via `respond_to?`/`instance_methods.include?`/
`const_defined?`/`ancestors.include?`); add `module Warning` with `[]`/`[]=` and
`suppress_keyword_warning`.
**Payoff/effort: 10/10** — best ratio in the slice.

### C2. `module_function` is a no-op stub (EASY–MEDIUM)
**Signature:** `undefined method 'fooM1'/'fooM3'/'fooO1Q1'/... for LangSendSpecs` —
the send fixture (`rubyspec/language/fixtures/send.rb`) uses bare `module_function`;
`Module#module_function` in `lib/core/class.rb:444` is `nil`-returning stub, so no
fixture method is callable.
**Affected:** send_spec — ~100 of its 115 failures trace to this single stub.
**Complexity:** easy for the `module_function(:name, ...)` form (copy method into the
module's eigenclass); medium for the bare modifier form (compiler must track
"module_function mode" in module bodies and emit singleton defs) — and it is the bare
form the fixture uses.
**Fix:** compile-time handling of bare `module_function` in module scope (mirror each
subsequent `def` into the eigenclass), plus a real runtime `module_function(*names)`.
**Payoff/effort: 9/10** — ~100 tests behind one mechanism.

### C3. `defined?` coverage gaps (MEDIUM)
**Signature:** `Expected "method"/"yield"/"super"/"constant"/... but got nil` (27x),
plus wrong "expression" answers. Failing forms: `defined?(yield)`, `defined?(super)`,
`defined?(recv.meth)` incl. nil-on-exception, private methods, class variables, some
constant/ivar edges.
**Affected:** defined_spec 43 (+ scattered `defined?` assertions in variables/predefined).
**Complexity:** medium — localized to the `defined?` special-casing
(`compile_calls.rb:476`) + small runtime helpers.
**Payoff/effort: 8/10** — one file, one code path, 43 tests.

### C4. `$!` (and `$@`) not wired to exception state (MEDIUM)
**Signature:** `Expected #<StandardError> but got []`, `Expected nil but got []`,
`undefined method 'backtrace' for []` — `$!` evidently reads as an empty array
sentinel instead of the current exception / nil.
**Affected:** predefined_spec ≈ 40–45 of its 135 (the single biggest bucket there);
also rescue_spec bits (`undefined method 'message' for nil`).
**Complexity:** medium — hook raise/rescue/ensure machinery to set, clear, and
*restore* `$!` (stack-like save/restore around rescue), map `$@` to `$!.backtrace`.
**Payoff/effort: 8/10** — localized to exception runtime.

### C5. Qualified/dynamic constant assignment + constant op-assign (MEDIUM, real codegen bug)
**Signatures:**
- constants_spec: 25× `wrong number of arguments (given 0, expected 1)` on
  `Mod::CONST = value` (compiled as a bad call instead of const store).
- optional_assignments: `uninitialized constant Object::A` on `A ||=` forms,
  `Expected [:evaluated] but got [:evaluated, :evaluated]` (receiver evaluated twice
  in `obj.attr += v`).
- assignments_spec: `uninitialized constant [:index, [:index, :__env__, 1], 3]::A` —
  **an AST/env s-expression leaking into the constant-scope name** when the op-assign
  target is env-captured inside a block. Genuine compiler bug worth fixing regardless.
**Affected:** constants ~25, optional_assignments ~20 (incl. double-eval), assignments ~10 → **~55**.
**Complexity:** medium — treat `scope::CONST = v` as const-store in the assignment
transform; cache receiver once for op-assign; fix the env-rewrite so it doesn't
rewrite the scope operand of `[:deref/const ...]` nodes.
**Payoff/effort: 8/10.**

### C6. Keyword-arguments correctness (MEDIUM-HARD, one workstream)
**Signatures:** kwargs land in the wrong bucket — `Expected [[{:a=>1}], {}] but got
[[], {:a=>1}]` (kw-vs-positional-hash split), `super` drops kwargs (`Expected
{:a=>"a",...} but got {}` — 29 of super_spec's failures), `**nil`/`**{}` mishandled
(`undefined method 'keys' for nil`, `Expected [] but got [{}]`), arity errors with
post-splat/kwarg params (`given 0, expected 4+` in method_spec).
**Affected:** keyword_arguments 26 + super ~29 + method ~15 + hash ~6 + block ~10 + def a few → **~85**.
**Complexity:** medium-hard, but a single coherent area: argument marshalling
(caller-side kw/hash tagging, callee-side splitting, super forwarding, `**splat`).
**Payoff/effort: 7/10** — biggest medium bucket; kwargs is already known-partial.

### C7. Regexp match globals `$~ $& $` $' $1..$9` (MEDIUM)
**Signature:** `Expected instance of MatchData, got nil`, derived globals all nil,
`Expected "foo" but got nil` after `=~`.
**Affected:** predefined ~25–30, match_spec 10, chunks of regexp/back-references (20)
and regexp_spec → **~50** (overlaps regexp-engine bucket).
**Complexity:** medium — `=~`/`match` must set a method-scoped (not block-scoped)
`$~` and derive `$&` etc. lazily. Frame-local global semantics are the tricky part.
**Payoff/effort: 6/10.**

### C8. Block-param & multiple-assignment destructuring protocol (MEDIUM)
**Signatures:**
- block_spec: 22× `undefined method 'b' for #<Class:singleton>` — parenthesized
  block params `|(a, b)|` never bind their variables (parsed as method call later).
- variables_spec: `to_ary`/`to_a` protocol failures — `Expected [1, Mock] but got Mock`,
  shape errors on nested splats; 11× missing TypeError from bad `to_ary`.
- variables_spec: 7× `undefined method '__get_raw' for [1, 2]` — internal Array
  accessor not reachable on **Array subclasses** (easy standalone bug).
**Affected:** block ~30, variables ~45 → **~75** (excluding overlap with strictness C10).
**Complexity:** medium — destructuring params reuses the masgn machinery; `__get_raw`
inheritance fix is easy and worth doing first.
**Payoff/effort: 6/10.**

### C9. Module constant-reflection methods missing (EASY)
**Signature:** `undefined method 'const_set'/'remove_const'/'public_constant'/
'private_constant'/'const_get' for ...` (const_get exists on Module but not on
eigenclasses).
**Affected:** constants ~14, optional_assignments 2, rescue 1, singleton_class 1 → **~18**.
**Complexity:** easy-to-medium — plain lib/core Module methods; caveat: consts are
compile-time entities here, so `const_set`-created constants only need to be visible
via `const_get`/dynamic lookup for the specs sampled.
**Payoff/effort: 6/10.**

### C10. Strictness long tail — expected exceptions never raised (MEDIUM, diffuse)
**Signature:** `Expected TypeError/ArgumentError/NameError/FrozenError/NoMethodError/
LocalJumpError to be raised but nothing was raised`. ~180 assertion sites in the 16
sampled outputs; minus ~38 SyntaxError ones (C13) → **~140 assertions, ~100+ tests**.
Sub-buckets: coercion checks (`#to_ary`/`#to_a` must return Array → TypeError),
frozen-object checks (def_spec 7), method visibility (private send → NoMethodError;
def 5, super 2), arity validation, `$!`/`$~` assignment type checks.
**Complexity:** each item easy; the aggregate is a rolling cleanup, not one fix.
**Payoff/effort: 5/10** — good filler work, steady conversion rate.

### C11. Pattern matching `case/in` unimplemented (HARD / project)
**Signature:** after the Warning gate (C1), remaining failures show `x in [a, b]`
parsed as a method call (`undefined method 'in'`, `undefined method '__case_value'`),
i.e. no parser/codegen support for patterns at all.
**Affected:** pattern_matching_spec **222** (largest single file in the slice).
**Complexity:** hard — parser + a full pattern-compilation pass (deconstruct/
deconstruct_keys, pin, find/alt patterns). Own project like Float.
**Payoff/effort: 4/10** (huge payoff, project-scale effort).

### C12. Regexp engine/literal gaps (MEDIUM-HARD / project bucket)
**Signature (regexp_spec):** 23× `Expected / foo / but got nil` plus option/source
issues (`"(?-mix:/)"`), back-references, anchors, repetition, subexpression calls.
**Affected:** regexp_spec 24 + back-references 20 + anchors 13 + modifiers 9 +
subexpression_call 8 + repetition 6 + grouping 5 + interpolation 5 + empty_checks 4
→ **~94** (excl. regexp/encoding 27 → C14).
**Complexity:** medium-hard; depends on the regexp engine's maturity — treat as its
own sweep after C7 lands (match globals overlap).
**Payoff/effort: 4/10.**

### C13. SyntaxError-expectation tests (WONTFIX-ish)
**Signature:** `Expected SyntaxError to be raised but nothing was raised` — these
specs feed bad source to `eval`/`ruby_exe`; the AOT helper's eval stub can't raise.
**Affected:** ~35–40 tests across block (15), predefined (8), hash (5), assignments (4),
rescue (4), regexp (4), delegation (3), etc.
**Fix:** optionally have the helper's `eval`/`-> { eval(...) }.should raise_error(SyntaxError)`
path run the snippet through the compiler's parser and raise SyntaxError on parse
failure — would convert a chunk cheaply, but low value. Otherwise mark wontfix.
**Payoff/effort: 3/10.**

### C14. Magic comments / encodings (WONTFIX-ish, known)
magic_comment_spec 54 (0 pass; needs `load`, dynamic require, real Encoding),
regexp/encoding_spec 27, encoding_spec 4 → **~85**. Encodings are stubs by design;
park until an encoding project exists.
**Payoff/effort: 2/10.**

### C15. Misc singletons (noted, unsampled or small)
- delegation_spec 23 — `def m(...)` triple-dot forwarding unsupported (10× arity
  errors); medium parser+codegen feature, self-contained.
- break_spec 27 — break-from-proc semantics: `LocalJumpError` (4), `break from
  proc-closure` unhandled (3), ensure-ordering; medium-hard control flow; overlaps
  proc/lambda/next specs.
- numbered_parameters_spec 18 — `_1`/`it` params unimplemented; medium parser feature,
  self-contained.
- constants resolution strictness (NameError on missing lexical scope, private
  constants, const_missing dispatch) — ~25 of constants_spec beyond C5/C9; medium-hard
  since resolution is largely compile-time.
- file_spec 11 + line_spec 10 — `__FILE__`/`__LINE__`; partially a harness artifact
  (specs run from a copied temp file); easy to investigate, may be cheap wins.
- predefined leftovers: `$LOAD_PATH.resolve_feature_path`, Fiber#resume missing,
  `STDOUT`/`$stdout` reassignment checks (~25).

---

## Ranked top-10 (payoff vs effort)

| # | Cluster | Est. tests | Effort | Notes |
|---|---------|-----------|--------|-------|
| 1 | C1 helper matchers/stubs (complain, have_*, Warning) | ~80 direct + un-gates ~100 | trivial (helper only) | Do first; de-noises every other cluster |
| 2 | C2 `module_function` real impl | ~100 | easy-medium | Single stub, single file dominates |
| 3 | C3 `defined?` gaps | ~43 | medium, localized | One code path |
| 4 | C4 `$!`/`$@` wiring | ~40 | medium, localized | Exception runtime only |
| 5 | C5 qualified-const assignment + op-assign double-eval | ~55 | medium | Includes real env-rewrite codegen bug |
| 6 | C6 kwargs correctness (incl. super forwarding) | ~85 | medium-hard | One coherent workstream |
| 7 | C8 destructuring (block params + masgn protocol, `__get_raw`) | ~75 | medium | `__get_raw` subclass bug is an easy first bite |
| 8 | C9 const reflection methods | ~18 | easy | lib/core only |
| 9 | C7 regexp match globals | ~50 | medium | Prereq for regexp bucket |
| 10 | C10 strictness sweep (TypeError/FrozenError/visibility/arity) | ~100+ rolling | easy each, diffuse | Continuous filler |

Hard/park: C11 pattern matching (222, own project), C12 regexp engine (~94).
Wontfix-ish: C13 SyntaxError-eval (~38), C14 magic comments/encodings (~85).

Estimated conversion if ranks 1–5 land: **~300–320 tests** (~16% of the slice) with
no architectural risk; adding 6–9 brings the reachable total to roughly **~530**.
