# Rubyspec triage: core/[a-h]* (array .. hash)

> **HISTORICAL — 2026-07-04 snapshot.** Most actionable items here have been
> executed over the 2026-07-04→06 loop. See [ANALYSIS.md](ANALYSIS.md) for current
> status (PASS 376 / CRASH 22 / COMPILE_FAIL 1, 9,302 tests passing @ `09872ec`) and
> [../KNOWN_ISSUES.md](../KNOWN_ISSUES.md) for live bugs. Kept for context, not as a live to-do.

Date: 2026-07-04. Source: `docs/spec_status.jsonl` + ~20 live `run_rubyspec` runs.
Slice totals: **10,265 failed assertions** across ~700 failing specs.

Per-directory failed counts: array 4442 (pack 3392 / non-pack 1050), file 1031,
enumerable 599, encoding 572, enumerator 555, hash 482, float 452, dir 400,
env 320, complex 310, exception 275, argf 238, fiber 224, basicobject 86,
binding 86, class 48, data 47, gc 33, conditionvariable 22, filetest 20,
comparable 18, false 5.

## Ranked clusters (payoff / effort)

### 1. Array#pack integer directives — ~2,583 fails — MEDIUM — score 10/10
- **Signature:** `undefined method '+' for nil` (missing `be_computed_by` matcher on
  data-table tests) and `Expected TypeError/ArgumentError to be raised but nothing was raised`.
- **Files:** `array/pack/{j,l,s,i,q,c,n,v,w}_spec.rb` = 764+484+484+440+144+80+80+80+27.
- **Cause:** `lib/core/array.rb:1861` pack handles only C/c/a/A/Z, silently *skips*
  unknown directives, and never validates modifiers or raises TypeError on non-int.
- **Fix sketch:** one generic integer emitter (width × endianness table for
  s/S/l/L/q/Q/j/J/i/I/n/N/v/V + `<`/`>`/`!`/`_` modifiers), `to_int` coercion with
  TypeError, ArgumentError on bad modifiers/short input. Plus add the missing
  **`be_computed_by` matcher to `rubyspec_helper.rb`** (trivial prerequisite; used by
  10 spec files, all pack data tables).
- Follow-on: string dirs a/b/h/m/u/x/z = **+358** (easy-medium); float dirs d/e/f/g
  = 396 → blocked on the Float project.

### 2. ENV hash-like method delegation — ~320 fails — TRIVIAL/EASY — score 9/10
- **Signature:** `undefined method 'reject'/'reject!'/'clear'/... for ENV`.
- **Files:** 42 failing env specs: reject 24, merge 21, update 21, filter 20,
  select 20, to_h 19, delete_if 16, keep_if 16, except 12, rassoc 10, replace 9,
  values_at 9, each_key/each_pair/each 24, ...
- **Fix sketch:** ENV is a singleton over getenv/setenv; implement each method as
  "snapshot to Hash → delegate → write back". Entirely formulaic, one file.

### 3. Glob engine: Dir.glob / Dir.[] / File.fnmatch — ~436+ fails — MEDIUM — score 8/10
- **Signature:** `undefined method 'glob' for Dir`, `undefined method 'fnmatch'/'fnmatch?' for File`.
- **Files:** dir/glob_spec 167, dir/element_reference_spec 111, file/fnmatch_spec 158.
- **Fix sketch:** one fnmatch pattern matcher (`*`, `**`, `?`, `[...]`, `{a,b}`,
  FNM_* flags) shared by File.fnmatch and a directory-walking Dir.glob/Dir.[].
  Self-contained new core file; no compiler work.

### 4. Enumerable module gap-fill — ~400 of 599 fails — EASY — score 8/10
- **Signature:** `undefined method 'none?' for #<EnumerableSpecs__Numerous>` etc. —
  methods exist on Array but not in the Enumerable module (`lib/core/enumerable.rb`
  has only 40 defs; `grep` is literally commented out).
- **Missing:** none? 33, tally 25, first 24, one? 23, find_index 22, grep 21,
  to_h 21, take 19, grep_v 18, take_while, drop, drop_while, uniq, minmax_by,
  each_entry, sum edge-cases; plus optional-pattern arg for all?/any?/none?/one?
  (`wrong number of arguments (given 1, expected 0)` — 21 fails in all_spec alone).
- **Fix sketch:** implement each in terms of `each` — mechanical. Remainder of the
  599 blocked on multi-value-yield semantics (`YieldsMulti` — compiler-level,
  "Expected false but got true") and enumerator-return-when-no-block.

### 5. Array set ops + to_h + try_convert — ~165 fails — TRIVIAL — score 8/10
- **Signature:** `undefined method 'intersection'/'&'/'union'/'difference'/'to_h'`.
- **Files:** intersection 44, union 42, difference 27, intersect? 14, to_h 24,
  try_convert 13.
- **Fix sketch:** &, |, -, intersection, union, difference, intersect? via
  hash-membership; to_h iterating [k,v] pairs (share with Enumerable#to_h);
  Array.try_convert via respond_to?(:to_ary).

### 6. Hash small-methods batch — ~230 fails — TRIVIAL/EASY — score 7/10
- **Signature:** `undefined method '>' for {:a=>1,...}`, `undefined method 'assoc'`,
  `'compare_by_identity'`, `'transform_keys!'`.
- **Files:** gt/gte/lt/lte 76 (subset-comparison, ~15 lines total), compare_by_identity 36
  (equal?-keyed mode flag — the one semantic one, medium), transform_keys 28
  (bang variant + hash-arg form), assoc 16, rassoc 16, to_h 17, try_convert 13,
  each_key 12, each_value 12.
- **Fix sketch:** implement <,<=,>,>= as pair-subset checks; assoc/rassoc as scans;
  transform_keys(hash=nil){} + !. compare_by_identity needs an identity-hash mode
  in the hash internals — split it out.
- Note: transform_keys also trips the known interpolated-symbol bug
  (`:"x#{v}"` → `:"x{v}"`) — compiler, tracked elsewhere.

### 7. Enumerator: Lazy methods + product family — ~340 fails — MEDIUM — score 6/10
- **Signature:** `undefined method 'grep' for #<Enumerator__Lazy>`,
  `undefined method 'product' for Enumerator`.
- **Files:** lazy/* 258 across 29 specs (grep 26, grep_v 26, zip 21, chunk 16,
  select 14, ...), enumerator/product* 81 across 7, next_values/peek_values 30.
- **Fix sketch:** Lazy pipeline exists in part; add grep/grep_v/zip/chunk/uniq/etc.
  as lazy-wrapping combinators; Enumerator.product is a small standalone class.

### 8. Exception introspection methods — ~150 fails — EASY/MEDIUM — score 6/10
- **Signature:** `undefined method 'full_message'/'detailed_message'/'receiver'` ,
  NoMethodError message-format mismatches ("Expected to be truthy" on message checks).
- **Files:** full_message 40, backtrace 25, no_method_error 25, detailed_message 20,
  exception_spec 15, equal_value 12.
- **Fix sketch:** full_message/detailed_message as formatted wrappers over message +
  (stub) backtrace; NoMethodError#receiver/#args/#private_call?; Kernel#exception
  coercion protocol. Real backtrace content is a separate hard problem.

### 9. File path-string methods — ~100 fails — EASY — score 6/10
- **Signature:** `wrong number of arguments (given 2, expected 1)` for basename
  (suffix arg unsupported), wrong edge cases ("/" → ""), missing to_str coercion.
- **Files:** basename 21, dirname 19 (level arg), extname 16, split 16, path 18,
  to_path 16.
- **Fix sketch:** pure string manipulation in lib/core/file.rb: basename(path, suffix),
  dirname(path, level=1), trailing-slash/root edge cases, TypeError on non-to_str.

### 10. printf/sprintf `__tmp_proc` compiler bug — 253 fails gated — MEDIUM/HARD — score 5/10
- **Signature:** `undefined method '__tmp_proc' for #<Object>` × 110 in
  file/printf_spec (253 fails total, 3 pass).
- **Cause:** spec drives everything through `it_behaves_like :kernel_sprintf,
  -> format, *args { File.open(...){} }` — a stabby lambda with rest-args whose body
  creates a nested proc; `__tmp_proc` isn't declared in that lambda's let
  (transform.rb:1050 region — same family as the fixed rewrite_lambda bugs).
- **Payoff note:** fix unlocks the whole :kernel_sprintf shared suite here AND in
  kernel/ (outside slice); actual pass-rate then depends on sprintf impl quality.
  Also needs Float::NAN/INFINITY constants (7 fails, trivial stubs).

## Project buckets (not loop fixes)

- **Float** (~1,200 in slice): float/ 452 + complex/ ~310 + pack d/e/f/g 396 +
  scattered enumerable/file bits. Known foundational gap — Float arithmetic is
  entirely stubbed. HARD, dedicated project.
- **Encoding** (~572): known stub family (compatible_spec 119, converter/* 150+).
  Mostly meaningless for a byte-oriented AOT runtime; consider mass-skip or a
  minimal US-ASCII/UTF-8 model. HARD/low value.
- **Fiber** (224): needs real coroutines (`undefined method 'resume'`). ARCHITECTURAL.
- **ARGF** (238): whole-object missing; medium IO project, low urgency.
- **binding/** (86): eval/binding — out of scope for AOT per policy.
- **Array subclass instantiation** (`MyArray[...]` → `wrong number of arguments
  (given 0, expected 2)`, 68 fails in slice_spec alone, MyArray used in 40 array
  spec files): `Array.[]` must not call subclass #initialize, but the comment at
  lib/core/array.rb:463 records that allocate-based attempts **segfault the
  self-hosted compiler** — this is a compiler bug to hunt, not a lib tweak. MEDIUM/HARD,
  high leverage across array/.

## Harness fixes (trivial, do first)

- Add `be_computed_by` matcher to rubyspec_helper.rb (blocks pack + encoding tables).
- ShouldNotProxy#method_missing prints `@result` (unset ivar → always "nil") instead
  of `result` — misleading failure messages (rubyspec_helper.rb:556).
