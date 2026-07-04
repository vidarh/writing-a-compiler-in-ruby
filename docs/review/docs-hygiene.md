# Documentation hygiene review — staleness & drift

*Reviewed: 2026-07-04, against HEAD `01234cd` (spec_status: PASS 342 / FAIL 1797 / CRASH 10 /
COMPILE_FAIL 5 / TIMEOUT 4; tests 5935 passed of ~36.9k).*

Recent major changes most docs predate (verified in git log):

- `c6d1f4f` — **Nested closure environments**: env layout is now `[0]=frame of allocating
  activation, [1]=parent env link, [2..]=captured vars`; per-activation `__wrapenv` wrapper envs;
  compile-time parent hops (`__env_hops`); `break` unwinds to the defining activation (now
  MRI-correct); `preturn` walks parent links to the root frame.
- `63b5875` — **`__proc_call_block` global DELETED**: lambda ABI slot 2 is now `__callblk__`
  (the call-time block, feeding `|&b|` params); `Object#__call_block__` deleted; `yield` /
  `block_given?` inside blocks use the env-captured `__closure__`; `proc { |&b| }` now works.
- `46a78f6` — `return` runs enclosing ensures and pops exception handlers.
- `4c7ecd8`/`f4c3424` — `Kernel#exit`/`Process.exit` raise SystemExit; `exit!`.
- `3d9c279` — `IO#write` raises IOError; IOError/EOFError moved to `lib/core/exception.rb`.
- `ab89d9d` — runtime constant table (`$__runtime_const_names/vals`); `Struct.new("Name")`
  registers `Struct::Name`.
- `88db001` + later — `rubyspec_helper.rb` rescues raises from `before :each` blocks and
  describe bodies.

---

## Findings: (file, stale claim, correction needed, effort)

### docs/KNOWN_ISSUES.md — **worst offender; header + several entries invalidated**

| # | Stale claim | Correction | Effort |
|---|---|---|---|
| 1 | Header "Last Updated 2026-02-10"; "Language Specs: 78 files, 3 passed / 28 failed / 47 crashed; 994 cases, 272 passed, 27%" | Replace the whole Current State block with a pointer to auto-generated `docs/spec_status.md` (now PASS 342 files / CRASH 10 / 5935 tests passing across 2158 files) so it can never rot again | small |
| 2 | **Issue 1 "Break from Blocks - Wrong Return Target"**: "`break` behaves like `return` - exits the DEFINER instead of the YIELDER"; root cause text describes the old flat env ("Blocks capture `__env__[0]` = frame pointer where block was CREATED"); "Two-slot env approach BLOCKED" | Resolved by `c6d1f4f` (nested envs): break resumes the defining activation right after the yielding call; commit demonstrates `[1,2].each{|x| [10].each{ break }; r << x }` now MRI-correct. Move to a fixed/history section; the "previous fix attempts" notes are obsolete | small |
| 3 | **Known Limitations ("Cannot Fix") item 5**: "A block/proc's own block parameter (`proc { |&b| ... }`) does not work... needs a calling-convention change (a dedicated call-block slot) — deferred as too invasive" | That exact calling-convention change shipped in `63b5875` (`__callblk__` = ABI slot 2). Delete/rewrite the entry; re-check core/proc call_spec / yield_spec / case_compare_spec, which it lists as crashed by this | small |
| 4 | **Issue 4 bullet** "`|&block|` (block param of a block/lambda) is unbound... reverted pending that" | Superseded by `63b5875` — `&b` binds from the `__callblk__` slot; `block_given?` inside blocks now env-captured. Verify and strike the bullet | small |
| 5 | Issues 0, 5, 8, 9 are long FIXED write-ups still sitting under "Active Issues" (hundreds of lines of investigation log) | Prune: move FIXED entries (with their valuable technique notes) to a `docs/bugs/` archive or a "Resolved" section; keep Active for genuinely open items (4, 6-send-path, 7, 10) | medium |
| 6 | "Test Framework Issues: `ScratchPad` - Test framework class not available; `fixture()` - not implemented" | Stale: `rubyspec_helper.rb` defines `ScratchPad` (record/recorded/clear/<<) and `run_rubyspec` inlines fixtures. Rewrite the section around the real remaining gaps | small |
| 7 | Issues 2 (keyword args) and 3 (compound expr after if/else) are undated 2025-era claims | Re-verify both against the current compiler; date-stamp or drop | small-medium |

### docs/TODO.md

| Stale claim | Correction | Effort |
|---|---|---|
| Header "Last Updated 2026-02-10"; same 994/272/27% and 78-file stats as KNOWN_ISSUES | Point at `docs/spec_status.md` | small |
| Priority 1.1 is a full duplicate of KNOWN_ISSUES issue 1 ("break exits DEFINER... two-slot env crashes self-compilation") | Fixed by `c6d1f4f` — delete; replace Priority 1 with something from the current burndown (e.g. Float, which is now the dominant blocker per MEMORY/burndown_triage) | small |
| "Completed" section ends at 2025-12-01 | Refresh or drop the section (git log is the record) | small |

### README_RUBYSPEC.md — **stale in nearly every line (2025-era)**

| Stale claim | Correction | Effort |
|---|---|---|
| "Status: Working: 4 specs passing (TrueClass#to_s, Integer arithmetic)" | 342 spec files pass, 5935 individual tests | rewrite whole file (small — it should mostly defer to CLAUDE.md + spec_status.md) |
| "Compiler Limitations: `unless` - use `if !`; `**` not supported; `method_missing` (causes segfault); Exceptions/raise - failures tracked via global variables; no `at_exit`" | All wrong today: unless/`**`/method_missing work; exceptions are implemented (raise/rescue/ensure, SystemExit, runtime handler stack); the helper rescues before-blocks/describe bodies | (same rewrite) |
| "rubyspec_helper.rb ... No exception support (uses failure counting instead)" | Helper now catches exceptions from examples, before-blocks, and describe bodies | (same rewrite) |

### CLAUDE.md (root)

| Stale claim | Correction | Effort |
|---|---|---|
| "Missing Language Features: **Exceptions**: Limited begin/rescue support (commented out for bootstrap); **Regular expressions**: Not implemented" | Exceptions are implemented (exception.rb runtime, ensure/return interaction, SystemExit, IOError/EOFError); Regexp has a pure-Ruby implementation (`lib/core/regexp.rb`, tracked core/regexp category). Float genuinely still stubbed — keep that one | small |
| "Docker Environment ... **All compilation happens inside Docker containers** for i386 compatibility" | LOCALDEV made the local `toolchain/32root` the default; `./compile` auto-detects and only falls back to Docker (`COMPILE_MODE` env). Docker is now the fallback/tgc-instrumentation path | small |
| File-organization list references **`docs/WORK_STATUS.md`** | File does not exist (NEXT_STEPS E4 also notes this). Either create it or drop the reference | small |
| Testing section omits `specbench` / `specbench-rubyspec` / `classify_failures` flow it elsewhere alludes to | Add one line each (Makefile already documents them) | small |

### docs/ARCHITECTURE.md — **describes the pre-closure-rework, pre-exception compiler**

| Stale claim | Correction | Effort |
|---|---|---|
| "Language Limitations: Exceptions (begin/rescue/ensure) - minimal support only; Regular expressions [unsupported]" | Same corrections as CLAUDE.md | small |
| "All development done in Docker containers for consistency"; Dependencies "Docker environment" | Local toolchain is the default path | small |
| No mention at all of: closure environment model (wrapper envs, parent links, hops), the lambda ABI, the exception runtime, the runtime constant table, eigenclass `$__ec_self__` globals | This is the MISSING-doc item below; at minimum add a "Closures" and an "Exceptions" subsection under Runtime System | medium |
| "Scoping" section omits several scope classes that exist (`funcscope.rb`, `sexpscope.rb`, `eigenclassscope.rb`, `globalscope` covered) | Minor completeness pass | small |

### docs/DEBUGGING_GUIDE.md

| Stale claim | Correction | Effort |
|---|---|---|
| "Pattern: ArgumentError Workaround (**No Exceptions**)" — "temporary workaround until exceptions are implemented"; "For error signaling without exceptions, print to STDERR and return nil" | Exceptions exist; the guide should now say "raise ArgumentError" and mark the `*args`+STDERR pattern as legacy to be burned down | small |
| "Bootstrap Issues ... Can't use exceptions (begin/rescue) in compiler source; Can't use regexps; Can't use `unless`" | Re-verify each; at least `unless` and basic rescue are long supported (RESCUEFIX plan exists precisely because the "no exceptions" assumption was false) | small |
| "Preprocessed files are in the **repository root** as `rubyspec_temp_*.rb`" | They are written to `tmp/rubyspec_temp_*.rb` (run_rubyspec `TEMP_SPEC="tmp/..."`); binaries in `out/` | small |
| `./run_rubyspec rubyspec/ --count-failures` | No such flag in run_rubyspec; remove | small |
| "See Also: `segfault_analysis_2025-10-09.md`, `bitwise_operator_coercion_bug.md`" | Neither file exists anywhere in the repo; drop or restore | small |
| "KNOWN LIMITATION: Top-level lambdas not supported / crash" | Almost certainly stale after the closure rework (top-level `[1].each{}` blocks/wrapper envs are exercised everywhere); re-verify and update | small |
| Missing: the debugging techniques that actually cracked the recent bugs — `setarch -R` (ASLR-off) determinism, hardware watchpoints, tgc canary/valgrind-in-docker, `tools/crash_trace.rb` | Add a "Heap corruption / layout-sensitive crash" section (much of the text already exists inside KNOWN_ISSUES 5/8 write-ups — move it here when pruning) | medium |

### docs/improvement-planner.md (included into README via `@docs/improvement-planner.md`)

| Stale claim | Correction | Effort |
|---|---|---|
| Whole "Slow Targets and Results Files" section: `make rubyspec-integer/-language/-regexp` targets writing `docs/rubyspec_*.txt` via tee, plus three rules about them | Those targets and files no longer exist (CLAUDE.md: "the old per-category docs/rubyspec_*.txt files are retired"). Makefile has `specs-parallel` / `specbench*` instead. Rewrite around `make specs-parallel` + `docs/spec_status.md` + `tools/classify_failures.rb`. This actively misguides the improvement-planner agent | small-medium |
| "30-second timeout per file" phrasing | Still the default SPEC_TIMEOUT but runs are parallel now; minor | small |

### README.md (root)

| Stale claim | Correction | Effort |
|---|---|---|
| "Status as of May 14th 2023" is the newest status; text contradicts itself (top: "compiler self-hosts"; bootstrap section: compiler1 "fails to produce a compiler2") | selftest-c (stage-2 self-compilation) has been a hard commit gate for months. Add a short current-status section (self-hosting green, rubyspec burndown numbers link, exceptions/regexp/bignums implemented, Float missing) and label the 2023 text as history | small-medium |
| "GC is disabled" | Still TRUE (`tgc_start` commented out in lib/core/base.rb:24) — keep, but worth stating in the new status block since it surprises | — |
| Documentation section links only CLAUDE/ARCHITECTURE/DEBUGGING/TODO | Add KNOWN_ISSUES.md and especially docs/COMPILER_WORKFLOW.md (the self-declared "durable entry point") | small |

### docs/NEXT_STEPS.md + docs/COMPILER_WORKFLOW.md (2026-06-26 proposals — partially executed)

| Stale claim | Correction | Effort |
|---|---|---|
| "Where things stand" table: "~4% files pass (4/80) ... 48 crash"; "Runner is **fully sequential** today"; "no per-stage instrumentation exists"; "30 s timeout → ~24 min/run lost" | A1/A2/A3/B1 are DONE: `tools/run_specs_parallel.rb` (parallel, tuned on ax52), `specbench_rubyspec.rb` (per-phase timing), `spec_status.jsonl` + `classify_failures.rb`, COMPILE_TIMEOUT + process-group kill in run_rubyspec. Mark executed items and refresh the baseline row (language specs now far beyond 4%) | medium |
| COMPILER_WORKFLOW: ax52 "**NOT yet provisioned** (verified 2026-06-26: bare machine)" | ax52 is provisioned and is where parallel runs happen (worker-tuning table in run_specs_parallel.rb measured there). Update | small |
| NEXT_STEPS "Proposed new plans to file" table (SPECBENCH/SPECFAST/SPECPIPE...) | Several shipped; annotate status so the backlog reflects reality | small |
| Both docs' framing of PEEPFIX ("should be reconsidered") vs. the still-active `docs/plans/PEEPFIX-*` plan | Resolve the contradiction: archive PEEPFIX or record the decision in the plan | small |

### docs/plans/ — plans obsoleted by the closure/block-channel rework

| Plan | Why stale | Correction | Effort |
|---|---|---|---|
| `BGFIX-fix-block-given-in-nested-blocks` (2026-03-01, log empty) | `block_given?` in nested blocks now resolved via env-captured `__closure__` + `rewrite_block_given` pass (`63b5875`) | Re-verify its acceptance case; archive or re-scope to just removing the compile_arithmetic.rb `@bug` workaround | small |
| `YIELDFIX-fix-yield-in-nested-blocks` (2026-02-28, log empty) | `yield` inside blocks reaches the defining method's block via env-captured `__closure__` (already worked pre-63b5875 per that commit; nested-env rework covers the crash cases) | Re-verify; archive or re-scope to removing the emitter.rb/globals.rb `@bug`s | small |
| `ENVFIX`, `CFEXPR`, `RESCUEFIX`, others created Feb–Mar 2026 | Predate 5 months of heavy churn; specs cite line numbers and failure modes that may have moved | Cheap re-validation sweep of all 20 active plans; archive dead ones (docs/plans/archived exists) | medium |

### docs/PATTERN_MATCHING_STATUS.md

- Fix-history section explains closure interaction in terms of the FLAT env
  (`[:index, :__env__, N]`, "skip condition in rewrite_env_vars"). With `__wrapenv`/hop
  rewriting, verify `rewrite_pattern_matching` still composes with the new walker rules
  (the `620a91b` "four scope-shape gaps" fix shows exactly this class of drift). Annotate the
  env references as historical. Effort: small.

### Scripts / Makefile / tools

- **Makefile** — current; targets are commented and match reality (specbench, specbench-rubyspec,
  specs-parallel, local toolchain). No action.
- **compile / compile2** — headers current (local-toolchain default, docker fallback). No action.
- **run_rubyspec** — header comment block is accurate and unusually well-maintained. No action.
- **tools/*.rb** — all reviewed headers (run_specs_parallel, specbench, specbench_rubyspec,
  bench_compile, classify_failures, crash_trace, compare_asm, asm_diff_counts, asm_ngram) are
  current and self-describing. One stray editor backup `tools/vm.rb~`. No action beyond cleanup.
- **rubyspec_helper.rb** — header ("Minimal MSpec-compatible implementation") fine; behavior
  (rescued before-blocks/describe bodies) is only documented in commit messages → belongs in the
  proposed harness doc or README_RUBYSPEC rewrite.

---

## Missing docs that would pay off

1. **`docs/CLOSURES.md` — closure environment design (HIGHEST VALUE).** The single largest
   undocumented subsystem, and the one where transform walkers must all agree or selftest-c dies
   (the `620a91b` regression was exactly four walkers disagreeing on scope shapes). Capture:
   - Env layout: `[0]=frame of allocating activation, [1]=parent env (0 at root), [2..]=captured
     vars` (captured vars live in the root env; wrapper envs are `[frame, parent]`).
   - Per-activation `__wrapenv` allocation (find_vars declares it; `__nest_proc_envs` post-pass
     injects prologue + repoints creation triples); hard scope boundaries at nested real `def`s.
   - Compile-time parent hops (`__env_hops`); `lookup_type` must unwrap hop chains (slots 0/1 raw);
     `class_body_env_size` unwraps hop chains.
   - Lambda ABI: `@addr(self, __closure__?, __callblk__, ...)` — slot 2 carries the CALL-TIME
     block (nil when none); `@closure` captured on the Proc at creation, no longer passed at
     invocation; `__call_with_self` blkarg contract (splat forbids `&blk`).
   - `break` semantics (unwind to defining activation's continuation via env[0]);
     `preturn` walks parent links to the root frame; interaction with ensure/handler-pop
     (`46a78f6`); lambda returns stay local.
   - yield/block_given? route through env-captured `__closure__` (rewrite_block_given pass).
   - The self-hosting gotchas already learned (never name a local `__closure__`; `:"#{}"` symbol
     literals don't interpolate; `$`-global auto-registration as the assignable lvalue).
2. **`docs/EXCEPTIONS.md` (or an ARCHITECTURE section).** raise/rescue/ensure implementation,
   the runtime handler stack, `return`-runs-ensures + handler pop, `$!`/re-raise, SystemExit exit
   path, why IOError/EOFError live in exception.rb (load order). Currently reconstructable only
   from commits.
3. **Runtime dynamic-constant machinery.** `$__runtime_const_names/vals` table, load-abort stubs,
   `Struct.new("Name")` registration, and the `E = 2` constant-leak issue (KNOWN_ISSUES #4) —
   one short doc tying these together.
4. **Harness reference.** What `rubyspec_helper.rb` + `run_rubyspec` actually guarantee now
   (rescued before/describe bodies, fixture inlining, active sed rewrites list per NEXT_STEPS A4,
   COMPILE_TIMEOUT/SPEC_TIMEOUT, JSONL schema). Replaces the rotten README_RUBYSPEC.md.
5. **`docs/WORK_STATUS.md`** — referenced by CLAUDE.md, never created; either create (journal) or
   remove the reference.
6. Restore-or-drop the two dangling DEBUGGING_GUIDE references
   (`segfault_analysis_2025-10-09.md`, `bitwise_operator_coercion_bug.md`).

## Suggested order of work

1. KNOWN_ISSUES.md + TODO.md refresh (delete fixed break/`|&b|` entries, point stats at
   spec_status.md) — small, stops active misinformation.
2. improvement-planner.md rubyspec-targets section — small, it feeds an agent.
3. CLOSURES.md — medium, highest architectural payoff.
4. CLAUDE.md / ARCHITECTURE.md limitation lists + Docker claims — small.
5. README_RUBYSPEC.md rewrite as harness reference — small-medium.
6. DEBUGGING_GUIDE refresh (exceptions exist; tmp/ paths; new crash-hunting techniques) — medium.
7. Plans re-validation sweep (BGFIX/YIELDFIX first) + NEXT_STEPS status annotations — medium.
