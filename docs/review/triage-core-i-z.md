# Triage: rubyspec/core/[i-z]* failures

Date: 2026-07-04. Source: `docs/spec_status.jsonl` (refreshed 2026-07-04) + 20 targeted
`run_rubyspec` runs + `docs/failure_signatures.txt`. Slice = every core/ directory
alphabetically i-z (includes math, mutex, queue, sizedqueue, refinement, systemexit,
threadgroup, tracepoint alongside the named ones).

**Slice totals: 1223 spec files, 998 non-PASS, 17,637 failed examples.**

## Per-directory failed-example counts (descending)

| dir | files | non-PASS | failed | passed |
|---|---|---|---|---|
| string | 139 | 132 | 4313 | 915 |
| kernel | 117 | 101 | 2834 | 704 |
| io | 80 | 74 | 1716 | 247 |
| marshal | 6 | 4 | 1339 | 4 |
| module | 83 | 78 | 1325 | 99 |
| time | 66 | 60 | 1134 | 53 |
| thread | 53 | 48 | 574 | 4 |
| numeric | 46 | 43 | 402 | 40 |
| range | 32 | 27 | 376 | 136 |
| math | 27 | 27 | 369 | 1 |
| symbol | 29 | 20 | 286 | 136 |
| process | 92 | 39 | 275 | 9 |
| proc | 23 | 19 | 264 | 66 |
| rational | 32 | 30 | 259 | 3 |
| sizedqueue | 16 | 16 | 245 | 0 |
| method | 25 | 19 | 241 | 49 |
| set | 54 | 40 | 219 | 64 |
| objectspace | 29 | 28 | 215 | 0 |
| regexp | 24 | 21 | 203 | 189 |
| integer | 67 | 33 | 202 | 401 |
| queue | 15 | 15 | 171 | 0 |
| tracepoint | 19 | 19 | 148 | 0 |
| matchdata | 27 | 21 | 119 | 54 |
| struct | 30 | 23 | 97 | 95 |
| (rest: random 78, unboundmethod 70, main 40, warning 36, mutex 27, refinement 22, nil 15, threadgroup 12, true 5, signal 4, systemexit 2) | | | | |

Key sub-total: **string/unpack/* alone = 1,955 failed** (45% of string).
Thread family (thread+queue+sizedqueue+mutex+condvar+threadgroup) = **~1,051 failed**.

---

## Ranked clusters (payoff vs effort)

Payoff/effort score: failed-examples convertible ÷ subjective effort (T=trivial ≤½day,
E=easy ≤1-2d, M=medium ~1wk, H=hard/multi-week).

### 1. String#unpack is a stub returning `[]` — TRIVIAL-to-MEDIUM, ~1,955 fails
- **Signature** (verified, `unpack/c_spec.rb`): every directive decodes to `[]`
  (`Expected [97] but got []`), plus `Expected ArgumentError ... nothing raised`
  for unknown directives, plus harness aborts on missing `be_computed_by` matcher.
- **Affected**: all 25 `string/unpack/*_spec.rb`. j_spec 480, s/l/i_spec 292 each,
  q 64, h/b/m/a ~44 each, remainder ~40 each.
- **Fix sketch**: implement the directive interpreter in `lib/core/string.rb`
  (or a new `lib/core/unpack.rb`): C/c/a/A/Z/b/B/h/H first (pure byte math, trivial),
  then s/S/l/L/n/N/v/V/i/I/j/J (fixnum + existing bignum for 32/64-bit unsigned),
  then m/u (base64/uuencode, easy), w/U (easy). Skip f/d/e/E/g/G (Float bucket) and
  p/P. Prerequisite: add `be_computed_by` matcher to `rubyspec_helper.rb`
  (16 string + 9 array files abort examples on it — see cluster 9).
- **Complexity**: medium overall; the first ~10 directives are trivial and cover the
  fattest files. **Score: 10/10 — single highest-payoff item in the whole slice.**

### 2. Kernel#open missing — TRIVIAL, ~300-440 fails
- **Signature** (verified, `io/read_spec.rb`): 77 of 187 fails in that one file are
  `undefined method 'open' for #<Object>`. 8 failing io/kernel spec files call bare
  `open(...)`; their summed failed count is 443 (not all attributable, but the abort
  cascades kill whole example groups).
- **Affected**: io/read 187, io/readlines 75, io/foreach 65, io/popen 68 (needs the
  `|cmd` pipe form), kernel/open, io/write et al.
- **Fix sketch**: `def open(path, *args, &block)` in `lib/core/object.rb` /
  kernel: delegate to `File.open`; if path starts with `|`, delegate to `IO.popen`
  (or raise NotImplementedError for pipes initially — still converts the majority).
- **Complexity**: trivial. **Score: 10/10.**

### 3. Symbol string-delegation sweep — TRIVIAL, ~240 of 286 fails
- **Signature** (verified, `symbol/slice_spec.rb`): `undefined method 'slice' for
  :symbol` (38×), plus TypeError-validation misses.
- **Affected**: slice 88, element_reference 61, inspect 38, match 24, casecmp 26,
  to_proc 11.
- **Fix sketch**: in `lib/core/symbol.rb` define `[]`/`slice`/`match`/`match?`/
  `casecmp`/`casecmp?`/`length`/`succ` etc. as `to_s.<method>` delegations (`[]` and
  `slice` returning String). `inspect` needs quoting rules for non-identifier symbols
  (`:"with spaces"`) — easy string scan.
- **Complexity**: trivial-easy. **Score: 9/10.**

### 4. Strict-parse Kernel#Integer + String#to_i(base) — EASY, ~180-250 fails
- **Signature** (verified): kernel/Integer_spec: 96× `Expected ArgumentError ...
  nothing raised` (invalid strings silently return 0), 4× base-prefix wrong
  (`Expected 8 but got 10`); string/to_i_spec: 47× `wrong number of arguments
  (given 1, expected 0)` — **String#to_i takes no base argument at all**.
- **Affected**: kernel/Integer 133, string/to_i 99 (minus a few bignum-truncation
  fails), spillover into kernel/Float_spec's Integer-adjacent examples.
- **Fix sketch**: one shared pure-Ruby numeric-string parser (sign, `0x/0o/0b/0d`
  prefixes, underscores, base 2-36) with a strict flag: `Kernel#Integer` uses
  strict (raise ArgumentError, honor `exception: false`), `String#to_i(base=10)`
  uses lenient prefix-parse. Also fixes `"0b1010".to_i(2)`-style cases elsewhere.
- **Complexity**: easy. **Score: 8/10.**

### 5. Format-engine validation (sprintf/printf/String#%) — EASY-MEDIUM, ~350-450 of 772 fails
- **Signature** (verified): string/modulo: 119× `Expected ArgumentError ... nothing
  raised`, 8× TypeError, 8× KeyError; kernel/sprintf: 12× each ArgumentError/
  TypeError + 8× KeyError; the rest is Float (`uninitialized constant Float::NAN`,
  Inf/NaN rendering, `%e/%f/%g`) and `String#to_f` gaps (`"0xA"`, `"-10.4e-20"`).
- **Affected**: kernel/printf 275, kernel/sprintf 260, string/modulo 237.
- **Fix sketch**: in the existing format code: raise ArgumentError on malformed/
  unknown directives, trailing `%`, flag misuse, arg-count mismatch; KeyError for
  missing `%{name}`; TypeError on non-coercible args; add `Float::NAN/INFINITY`
  constants (values can be stubbed until Float lands) to stop whole-group aborts.
  The Inf/NaN/precision rendering half stays in the Float bucket.
- **Complexity**: easy-medium (pure Ruby, one engine, three spec files).
  **Score: 7/10.**

### 6. Missing easy String methods (case/byte family) — TRIVIAL-EASY, ~250 fails
- **Signature** (verified, casecmp_spec): `undefined method 'casecmp' for "a"`,
  `casecmp?` likewise.
- **Affected**: casecmp 66, bytesplice 59, byteindex 53, byterindex 46, chomp-edge/
  misc smaller files.
- **Fix sketch**: `casecmp`/`casecmp?` = `downcase <=> downcase` (ASCII-only fine
  for now); byteindex/byterindex/bytesplice = byte-slice operations on the existing
  byte buffer. All pure `lib/core/string.rb` additions.
- **Complexity**: trivial-easy. **Score: 7/10.**

### 7. Set method-gap sweep — EASY, ~150-219 fails
- **Signature** (verified, set/subtract): `undefined method 'subtract' for
  #<Set: {:a,:b,:c}>` — Set is pure Ruby, just incomplete.
- **Affected**: 40 failing files × small counts: compare_by_identity 34, divide 18,
  flatten 13, join/filter/reject/select/comparison ~10 each, delete_if/keep_if/
  initialize 8 each...
- **Fix sketch**: fill in `lib/core/set.rb`: subtract, divide, flatten(!),
  join, filter/select/reject(!), keep_if/delete_if, <=>, ^, compare_by_identity.
  Mechanical; each method flips a whole small file.
- **Complexity**: easy (grind). **Score: 6/10.**

### 8. Module constant reflection: const_get & const_source_location — MEDIUM, ~155 fails
- **Signature** (verified, module/const_get): `undefined method 'const_get' for
  ConstantSpecs...` (16+), `Expected NameError ... nothing raised`.
- **Affected**: const_get 76, const_source_location 79; also feeds const_defined?/
  constants edge cases and module/autoload_spec (144) partially.
- **Fix sketch**: there is already a runtime constant registry used by
  `__runtime_const_lookup` / Struct name registration (`lib/core/struct.rb:49`);
  implement `Module#const_get(name, inherit=true)` over it with scoped `A::B`
  parsing and NameError on miss. const_source_location can return `["", 0]`-style
  stubs only where the constant exists (partial credit). Autoload itself is a
  separate, harder story (code loading).
- **Complexity**: medium. **Score: 5/10.**

### 9. mspec-harness helpers missing (be_computed_by, have_method, with_timezone) — TRIVIAL, unblocks ~50 spec files
- **Signature** (verified): `undefined method 'be_computed_by'` aborts examples in
  16 string/unpack + 9 array/pack files; `have_method` aborts in struct/new;
  signature file shows `with_timezone` missing for 22 time files.
- **Fix sketch**: add to `rubyspec_helper.rb`: `be_computed_by` matcher (calls
  `@method` on each source with args, compares), `have_method`/`have_instance_method`
  matchers, `with_timezone(name){ }` helper (set/restore ENV["TZ"] — even a
  yield-only stub stops the aborts). Doesn't flip files green by itself but is a
  prerequisite multiplier for clusters 1 and the time bucket.
- **Complexity**: trivial. **Score: 6/10 (multiplier).**

### 10. Proc/Method pure-Ruby combinators: curry, compose, case_compare — EASY, ~130 fails
- **Signature** (verified, proc/curry): `undefined method 'curry'`; 12×
  ArgumentError-on-lambda-arity not raised.
- **Affected**: proc/curry 46, proc/compose 34, method/compose 24, proc/case_compare 25.
- **Fix sketch**: `Proc#curry` (pure Ruby, uses #arity + #lambda?), `Proc#>>`/`#<<`,
  `Method#>>`/`#<<` (`method(:x).to_proc` composition), `Proc#===` → call.
  Needs working `Proc#lambda?`/`#arity` (mostly present).
- **Complexity**: easy. **Score: 5/10.**

---

## Known big buckets — note, don't dig (per instructions)

- **Marshal (by design NotImplementedError): 1,339 fails** in 6 files (load 451,
  restore 451, dump 401). Single bucket; ignore for burndown ranking.
- **"Real Time" project: 1,134 fails** across 66 files. Verified time/now runs but
  `Time.now(in:)` arity fails, `Process::CLOCK_REALTIME` missing, `with_timezone`
  helper missing, SubTime (subclass construction) broken. Zone/strftime machinery is
  a dedicated project; the harness helper + arity fixes above shave the edges only.
- **Thread family unimplemented: ~1,051 fails** (thread 574, sizedqueue 245, queue
  171, mutex 27, condvar 22, threadgroup 12). `Thread.current` undefined. HARD —
  needs a threading runtime. Queue/SizedQueue *could* be done single-threaded-
  degenerate for partial credit, but most examples spawn threads. Bucket.
- **Float bucket spillover (i-z share ≈ 1,100+)**: kernel/Float 297, numeric/step
  205, math 369 (Math is all Float), rational ~259 (float-interop heavy), plus the
  Float half of sprintf/printf/modulo and range/bsearch's float mode. All blocked on
  the known "Float is entirely stubbed" project.
- **Code loading: ~700 fails** (kernel/require 268, load 190, require_relative 98,
  module/autoload 144) + kernel/eval 66. Static compiler — dynamic load/eval is
  architecturally hard. Bucket; only spec-adjacent error-raising bits are winnable.
- **io encoding stubs: ~470** (encode 161, internal_encoding 150, external_encoding
  117, set_encoding 42) — encoding-machinery bucket, plus `IOSpecs.new_io` fixture
  aborts 24 io files (worth one look: likely a single fixture-level missing method).
- **process 275 / tracepoint 148 / objectspace 215 / refinement 22**: OS-level spawn
  semantics, tracing hooks, heap enumeration, refinements — all hard, low
  payoff-per-effort; leave.
- **method/proc parameters + source_location (~250)**: needs compiler-emitted
  parameter/location metadata. Medium-hard; worthwhile eventually since
  method/parameters_spec alone is 104, but it's compiler work, not lib work.
- **range/bsearch (110) & cover (73)**: bsearch exists but misbehaves (receiver-nil
  aborts suggest the `@range` before-block or beginless/endless literal handling
  breaks); float-mode halves are Float-blocked. Medium.
- **regexp (203)**: engine mostly passing (189 passed); remaining fails are
  validation (RegexpError/TypeError/ArgumentError not raised) + encoding constants
  (Shift_JIS etc.). Easy-medium grind, moderate payoff.

## Suggested execution order (payoff-weighted)

1. Harness helpers (#9, half a day) → 2. Kernel#open (#2) → 3. String#unpack core
directives (#1) → 4. Symbol sweep (#3) → 5. Integer()/to_i(base) (#4) →
6. String case/byte methods (#6) → 7. Format validation (#5) → 8. Set sweep (#7) →
9. Proc combinators (#10) → 10. Module#const_get (#8).

Items 1-6 are ≤1 week combined and convert an estimated **~2,700-3,000 failed
examples** — roughly 17% of the whole i-z slice — without touching any hard
subsystem (Float, threads, Time, Marshal, code loading).
