# Cleanup review — post crash-fixing session

Date: 2026-07-04. Scope: strictly NON-STRUCTURAL cleanup (comments, dead code,
debris, litter). Files reviewed: transform.rb, compiler.rb, compile_class.rb,
compile_calls.rb, compile_control.rb, treeoutput.rb, classcope.rb, emitter.rb,
lib/core/*.rb, rubyspec_helper.rb, test/selftest.rb, tmp/, repo root.

Ground truth used to judge staleness:
- `__proc_call_block` / `__call_block__` globals were DELETED (63b5875);
  block channels now ride the ABI + env.
- Envs are NESTED: `[0]=__stackframe__, [1]=__envparent__, [2..]=vars`
  (c6d1f4f, 620a91b). Flat-env descriptions are stale.
- Lambda/block defun ABI is `@addr(self, __callblk__, __env__, *args)`;
  `__closure__` in a block body aliases the env-captured defining-method block.

---

## 0. BUG (not cleanup) — CONFIRMED live bug, fixed during review (pending gate verification)

**lib/core/object.rb:633 and 637 — `instance_eval`/`instance_exec` called
`__call_with_self` without the `blkarg` slot.** The contract is
`__call_with_self(newself, blkarg, *__copysplat)` (lib/core/proc.rb:64;
lib/core/method.rb:25), and every other caller passes it explicitly
(lib/core/class.rb:419/425/432/438 pass `nil`; lib/core/object.rb:174 passes
`blk`). `block.__call_with_self(self)` left `blkarg` unset and
`block.__call_with_self(self, *args)` routed the FIRST USER ARGUMENT into the
block channel, shifting the rest. Root cause: `instance_eval`/`instance_exec`
were added 2026-07-01 (e2b9271) and not updated when 63b5875 (2026-07-04) grew
the `__call_with_self` signature with the `blkarg` parameter.

Status: the two-line fix (`__call_with_self(self, nil)` /
`__call_with_self(self, nil, *args)`) was applied to the working tree by the
coordinating session during this review (uncommitted; `git diff
lib/core/object.rb` shows exactly those two lines changed). This review
session was read-only and did not apply or independently re-test the fix; the
coordinator reports a compiled repro returning the MRI-correct `[1, 2, 42]`.
Pending: gate verification (selftest + spec sweep) and a DEDICATED commit —
keep it separate from any cleanup commit.

---

## 1. Stale / wrong comments

| Loc | Problem | Fix | Effort |
|---|---|---|---|
| transform.rb:451 | Comment says Proc#call invokes the defun as `@addr(self, __closure__, __env__, *args)` — slot 2 is `__callblk__`; contradicts lines 454–458 and the code right below | Change `__closure__` → `__callblk__` in the prototype | minutes |
| transform.rb:1405 | `# Proc#call sets @env[1] to caller's stackframe for break support` — under nested envs slot 1 is `__envparent__`, the stackframe is slot 0 (cf. 1576–1580) | Reword to slot 0 / `__stackframe__`, or delete | minutes |
| transform.rb:1633 | `rest_sym = rest.is_a?(Symbol) ? rest : rest` — both branches identical; the "Extract the symbol if needed" comment (1631–1632) describes something the code doesn't do | `rest_sym = rest`, drop the comment | minutes |
| classcope.rb:240–250 | Duplicated `klass_size` doc block with CONFLICTING content: 241–242 says "multiple of @vtableoffsets.max", 247–248 says "is @vtableoffsets.max" | Merge; keep the accurate slots-not-bytes version (247–250) | minutes |
| lib/core/class.rb:321–324 | Comment calls `define_method` a "runtime fallback no-op … do nothing rather than crash" — directly contradicts the real `$__dm_classes`/`$__dm_tables` registry implemented below (4dc9d67) | Drop the "no-op" framing | minutes |
| lib/core/class.rb:310–320 | Large stale FIXME design musing (vtable attachment, Symbol type-tagging) superseded by the working registry approach | Delete or trim to describe the registry | minutes |
| lib/core/exception.rb:40–44 | "MISSING FEATURES" list claims typed rescue (#2), `rescue => e` binding (#3) and ensure blocks (#5) are missing — all implemented (`@rescue_classes` machinery; 46a78f6 ensure-on-return) | Remove the done items; verify #4/#6/#7 individually | minutes |
| lib/core/exception.rb:407 | "$! holds the current exception message" — it holds the exception OBJECT | Reword | minutes |
| lib/core/object.rb:518–521 | Two back-to-back, mutually inconsistent doc comments for `clone` (one claims frozen-state copying, one disclaims it) | Keep the accurate second block, delete 518–519 | minutes |
| lib/core/object.rb:591–595 | `index` stub: stale "WORKAROUND: No exceptions" comment + `STDERR.puts("ArgumentError: …")` — exceptions exist now | `raise ArgumentError` and drop the stale comment | minutes |
| lib/core/array.rb:1824–1826, 1838–1840 | `collect!`/`map!` carry a copy-pasted comment describing the NON-destructive collect ("Creates a new array…") | Reword to describe in-place mutation | minutes |
| lib/core/stubs.rb:33 | Orphan breadcrumb `# raise is now implemented in lib/core/kernel.rb` | Delete | minutes |
| lib/core/array_base.rb:31 | Old growth formula left in a comment above the live s-exp version | Delete the commented formula | minutes |

Checked and NOT stale: proc.rb ABI comments (current), io.rb write/IOError
comments (current), transform.rb:123 hash-splat TODO (genuinely open),
kernel.rb / process.rb exit/exit! (no duplicate remains after f4c3424),
no `__proc_call_block`/`__call_block__` references survive anywhere in
compiler or lib/core sources (only in gitignored tmp/ repros).

## 2. Dead code / debug leftovers

| Loc | Problem | Fix | Effort |
|---|---|---|---|
| transform.rb:879 | Commented-out `#STDERR.puts v.inspect` | Delete | minutes |
| transform.rb:987 | `return [],env, false if !e` — three values where the convention (line 1238 and all callers) is two; the `false` is dead | `return [], env` | minutes |
| transform.rb:1239 | Commented-out old one-liner kept next to the FIXME at 1235 | Delete (optional) | minutes |
| treeoutput.rb:68–69 | "uncomment to see" + commented DEBUG print | Delete both lines | minutes |
| treeoutput.rb:428 | Commented-out debug `STDERR.puts` | Delete | minutes |
| emitter.rb:253 | Commented-out debug `STDERR.puts` | Delete | minutes |
| emitter.rb:209–210 | Commented-out `:ivar` dispatch branch that is ALSO stale — calls `load_instance_var(aparam)` but the method now takes `(ob, aparam)` | Delete both lines | minutes |
| emitter.rb:295, 325, 602 | Orphan methods `save_to_indirect`, `loaddouble`, `load_ptr` — zero callers project-wide (`save_indirect`/`storedouble` are the live ones) | Delete after a final grep | minutes |
| emitter.rb:129, 133, 141 | Trailing commented-out alternative register constructions (`# ster.new(:eax)` etc., one mangled) | Delete | minutes |
| classcope.rb:191 | Commented-out debug print — but it has an intentional explanatory paragraph (185–190) framing it as a layout-debugging aid | Keep or delete per taste; lowest priority | minutes |
| lib/core/object.rb:280–284 | Commented-out `printf` stub + stale FIXME ("Add splat support… so the below works") — `printf` is fully implemented at :453 via `__sprintf` | Delete the block | minutes |
| lib/core/array.rb:745–747 | DUPLICATE `collect!` definition — empty stub silently shadowed by the real implementation at 1827–1835 | Delete the stub (742–747) | minutes |
| lib/core/array.rb:1567 | Commented-out `#STDERR.puts "FLATTEN: …"` | Delete | minutes |
| lib/core/array.rb:1669–1674 | Commented-out alternate `index` implementation with stale "fails when compiling the compiler" note; block form now implemented at 1654–1662 | Delete | minutes |
| lib/core/array.rb:519 | Commented-out dead line in `__range_get` | Delete | minutes |
| lib/core/array.rb:314–316, 2297–2299 | Commented-out `def &` / `def \|` with no rationale (unlike the documented disabled `def -` at 361–366) | Delete or add the same rationale | minutes |
| lib/core/class.rb:17 | Commented-out debug `%s(printf "class object: %p …")` | Delete | minutes |
| lib/core/object.rb:587 | `eval` stub prints to STDERR on every call — noisy | Silence or keep once-only | minutes |

## 3. Compiler driver files (compiler.rb, compile_class.rb, compile_calls.rb, compile_control.rb)

No lingering `__proc_call_block`/`__call_block__` references in these four
files; remaining `__closure__` mentions are all correct (method defun ABI or
class/eigenclass body closure setup). compile_control.rb is clean, and its
compile_break NOTE (:381–383, `__env__[0]` = definer's frame) matches the
nested-env layout.

| Loc | Problem | Fix | Effort |
|---|---|---|---|
| compiler.rb:913–914 | Live `STDERR.puts "DEBUG: Malformed destructuring target…"` tripwire on a shipped code path | Delete both lines (spot-verified) | minutes |
| compiler.rb:658–661 | Stale FIXME paragraph: "a single, shared, environment … for the two lambdas … unavoidable" — the lambdas were refactored into compile_whens/compile_case_test (cf. note at 592–593), and shared-env is superseded by nested envs (spot-verified text) | Delete the paragraph | minutes |
| compiler.rb:1429–1444 | "Attempt at fixing segfault" block: locals `cmd`/`r` assigned nil and unused; only consumers are the commented-out alternate dispatch (incl. debug print at 1440) | Delete commented alt-impl + unused locals; KEEP the bare `exp` lift-var workaround | minutes |
| compiler.rb:598, 603 | Commented-out debug `STDERR.puts` in compile_case_test | Delete | minutes |
| compiler.rb:1524 | Commented-out `#warning("INFO: Max vtable offset…")` | Delete | minutes |
| compiler.rb:244, 815, 1425 | Commented debris (`#@e.bsslong`, `# trace(...)`, `#trace(...)`) | Delete | minutes |
| compiler.rb:447–452 | compile_rescue effectively dead ("shouldn't be called"; else_body ignored) — LOW CONFIDENCE: still a `:rescue` @@keywords dispatch target | Confirm no bare `:rescue` node reaches compile_exp before removing | minutes + verify |
| compiler.rb:872 + compile_calls.rb:318, 503 | Literal list `[:call, :callm, :safe_callm, :lambda, :proc]` duplicated verbatim in three arg-wrap guards | Hoist to one constant (e.g. `CALL_FORMS`) | minutes |
| compile_class.rb:22 | Commented-out `@e.comment` | Delete | minutes |
| compile_class.rb:64 | Dangling trailing comment on the return value | Delete | minutes |
| compile_calls.rb:536–537 | Commented-out `#warning`/`#error` in the `__send__` fallback | Delete | minutes |
| compile_calls.rb:580–588 | `# if ob != :self` / `# end` pair around "Evicting self" — documented-dead code behind a FIXME ("commenting out for now") | Decision item (keep FIXME or delete block), not blind deletion | minutes |

NOT stale (checked, leave alone): compile_class.rb:19 FIXME ("Replace
'__closure__' with the block argument name") is still open and accurate — it
concerns the METHOD defun ABI slot (line 20 hardcodes
`[:self, :__closure__] + args`), unrelated to the lambda `__callblk__` rename.
Likewise compile_calls.rb:57 ("hardcoded to 2 (self + __closure__)") is
accurate for the method ABI.

## 4. Test harness (rubyspec_helper.rb, test/selftest.rb)

Neither file references the deleted `__proc_call_block`/`__call_block__`
globals. selftest.rb:732–736 env-layout comment ([0]=__stackframe__,
[1]=__envparent__, [2]=__closure__) matches its expectation string exactly —
current, leave as is.

| Loc | Problem | Fix | Effort |
|---|---|---|---|
| rubyspec_helper.rb:259 | `STDERR.puts("Mock: No expectation set for …")` fires on every unstubbed call — stderr spam | Delete the print, keep the `nil` return | minutes |
| rubyspec_helper.rb:556 | LATENT BUG in failure message: interpolates `#{@result.inspect}` but the local is `result`; `@result` is an unset ivar, so the message always shows nil (spot-verified) | `@result` → `result` | minutes |
| rubyspec_helper.rb:630–631 vs 158–322 | MockExpectationStub defines `once`/`twice` but Mock does not — `mock(x).should_receive(:y).once` on a real Mock falls into method_missing (stderr + nil, breaking the chain) | Add no-op `once`/`twice` to Mock for parity | minutes |
| rubyspec_helper.rb:1097–1112, 1115 | Fully commented-out MockInt class with stale "DISABLED: Causes crash during class definition" note; `mock_int` (1114) no longer uses it; `# MockInt.new(value)` at 1115 dead | Delete the commented class + dead line (verify a compile; crash note may be outdated) | minutes + verify |
| rubyspec_helper.rb:1043–1047 | Stale FIXME header "fake values for 32-bit compatibility … don't actually test bignum behavior" — contradicted by 1050–1051 ("Now that we have large integer literal support" + the real value) | Delete 1043–1047 | minutes |
| test/selftest.rb:630–636 | `mock_preprocess` never called from selftest.rb (spot-verified; body all commented except a discarded `mock_parse`) — but note twins exist in selftest2.rb:565 / selftest_minimal.rb:566 | Delete the method | minutes |
| test/selftest.rb:65 | Commented-out `#require 'value'` | Delete | minutes |
| test/selftest.rb:184 | Commented-out sort expectation superseded by live tests at 206–207 | Delete | minutes |
| test/selftest.rb:24 | `#$quiet = true` toggle debris above the live `$quiet = false` | Delete | minutes |

test/ directory backup debris (deletable): `test/#defvar.rb#` (Emacs
autosave) plus `~` backups: absolute_minimal.rb~, compiler.rb~, regalloc.rb~,
runselftest.rb~, selfhost.rb~, selftest.rb~, selftest-reduced.rb~,
spec_helper.rb~, test_stabby_block.rb~. Flag-only (do NOT auto-delete):
test/selftest2.rb, test/selftest_minimal.rb, test/selftest_mini.rb coexist
with the canonical test/selftest.rb, and the Makefile still references
out/selftest2.l (Makefile:48–58, partly commented-out recipe) — confirm
harness references before touching.

## 5. Editor backup litter inside lib/core/ (untracked, gitignored-adjacent)

`lib/core/` contains stale editor backups that greps keep hitting:
`array.rb~`, `object.rb~`, `kernel.rb~`, `string.rb~`, `fixnum.rb~`,
`integer.rb~`, `hash.rb~`, `class.rb~`, `#array.rb#`, `#object.rb#`.
`kernel.rb~` still contains the OLD pre-runtime-constants stub code, so these
actively mislead searches. Fix: `rm lib/core/*~ lib/core/\#*\#`. Effort: minutes.

## 6. tmp/ repro inventory (389 files, all gitignored via `tmp/*`)

All dated Jul 3–4 (this crash-fixing session). Two classes:

**Canonical repros — KEEP** (referenced by commit messages and/or memory notes):
`tmp/bk6.rb`, `tmp/hop1.rb`, `tmp/ac2.rb`, `tmp/st5.rb`, `tmp/mc6.rb`,
`tmp/blk1.rb` (the first five are cited in memory/commits; blk1 additionally
appears in a commit body). Consider promoting these six to
`test/repros/` or listing them in docs so they survive a `tmp/` purge.

**Disposable — safe to purge:** the remaining ~380 one-off minimizations
(`su1..su20`, `ms*` ×14, `um*` ×13, `ac1..ac13` minus ac2, `px*` ×11,
`lm*` ×11, `dm1..dm10`, `cs1..cs10`, `zs*`, `wr*`, `sn*`, `sio*`, `fz*`,
`sb*`, `rs*`, `mn*`, `mc*` minus mc6, `lam*`, `fl*`, `ds*`, `bk1..bk5`,
`df*`, `cap[A-F,U]*`, `bg*`, `cmp*`, `cd*`, `ec*`, `es*`, `hop2..3`, etc.),
plus regenerated `tmp/rubyspec_temp_*` runner outputs. Fix:
`git clean -fX tmp/` AFTER copying the six canonical files out. Effort: minutes.

## 7. Repo-root litter

| Item | Status | Fix | Effort |
|---|---|---|---|
| `selftest_errors.tmp` | TRACKED, empty, from Feb | `git rm`, add `*.tmp` to .gitignore | minutes |
| `foo^bar/` | Empty stray directory (Jul 1), untracked | `rmdir 'foo^bar'` | minutes |
| `.#foo` | Dangling emacs lock symlink from 2016 (ignored via `.*`) | Delete | minutes |
| `.gitignore~` | Editor backup (ignored via `*~`) | Delete | minutes |
| `rubyspec_temp_include_directive_vs_call_spec.rb`, `rubyspec_temp_include_simple_test_spec.rb` | Untracked runner temps left in ROOT instead of tmp/ | Delete | minutes |
| `debug_huge_number.rb`, `debug_parse.rb`, `debug_parser_if.rb`, `debug_tokenize.rb`, `debug_transform.rb`, `debug_spec.sh`, `test_progressive.sh`, `mybin` | Untracked debug scripts in root (ignored via `debug_*`/`test_*`) | Delete or move under tools/ | minutes |
| `bisect-parse-error.rb`, `verify_all_29_specs.txt`, `verify_all_specs.sh`, `count_specs.sh`, `survey_specs.sh`, `extract_minimal_specs.sh`, `compile2` | TRACKED one-off investigation scripts in root | Decide: move to tools/ or `git rm` (needs owner call — borderline structural) | hour |
| `docs/plans/error-log.jsonl` | Untracked improve-cli run log (Feb 19–Mar 9) misfiled under docs/plans | Delete; it belongs to the improve harness, not the repo | minutes |
| vgcore / core dumps | NONE found (checked root + depth 2) | — | — |
| `Makefile:53–58` | Commented-out old selftest2 build/diff recipe | Delete or keep as documented workflow; low priority | minutes |

## Top 15 by value-for-effort

1. **object.rb:633/637 missing `blkarg` in `__call_with_self`** — CONFIRMED live bug; two-line fix already in the working tree (uncommitted), needs gate run + its own commit (NOT the cleanup commit).
2. compiler.rb:913–914 live DEBUG STDERR tripwire on the destructuring path; minutes.
3. transform.rb:451 stale `__closure__`-in-ABI comment — the exact confusion this session's ABI change resolved; minutes.
4. rubyspec_helper.rb:556 `@result`-vs-`result` failure-message bug — every falsy-assertion failure prints the wrong value; minutes.
5. lib/core/array.rb:745 duplicate empty `collect!` silently shadowed by the real one at 1827 — dead code that reads like the implementation; minutes.
6. lib/core/exception.rb:40–44 "MISSING FEATURES" list claiming implemented features (typed rescue, `rescue => e`, ensure) are missing — actively misleads triage; minutes.
7. lib/core/class.rb:310–324 stale "define_method is a no-op" comment + obsolete FIXME above a real registry implementation; minutes.
8. Editor backups in lib/core/ AND test/ (`*~`, `#*#`) — ~20 files that pollute every grep with pre-fix code; one `rm`; minutes.
9. tmp/ purge (≈380 disposable files) with the six canonical repros (bk6, hop1, ac2, st5, mc6, blk1) preserved/promoted; minutes.
10. compiler.rb:1429–1444 "Attempt at fixing segfault" leftovers — unused `cmd`/`r` locals + commented alt-dispatch (keep the live lift-var line); minutes.
11. transform.rb:1405 `@env[1]`-stackframe comment contradicting the nested-env layout (slot 1 is `__envparent__`); minutes.
12. rubyspec_helper.rb Mock trio — :259 stderr spam, missing `once`/`twice` parity (630–631), dead MockInt block (1097–1115); minutes.
13. classcope.rb:240–250 conflicting duplicated `klass_size` doc + emitter.rb:209–210 stale commented `:ivar` branch (wrong arity) + orphan emitter methods (295/325/602); minutes.
14. Root/tracked litter batch: `selftest_errors.tmp` (tracked, empty), `foo^bar/`, root `rubyspec_temp_*` strays, `docs/plans/error-log.jsonl`, `.#foo`, `.gitignore~`; minutes.
15. lib/core/object.rb pair: dead `printf` stub + done-FIXME (280–284, implemented at :453) and contradictory duplicated `clone` doc (518–521); minutes.

---

Provenance note: sections 1, 2, 5–7 come from this session's direct review +
two sub-reviews; sections 3 and 4 were consolidated from
`cleanup-compile-partial.md` and `cleanup-harness-partial.md` in this
directory (relayed sub-agent findings; line numbers spot-checked at
compiler.rb:658/913, rubyspec_helper.rb:556, selftest.rb:630 — all correct).
The two partial files are superseded by this document and can be deleted.
Working-tree state at review end: `lib/core/object.rb` carries the uncommitted
two-line BUG fix described in section 0; everything else untouched.
