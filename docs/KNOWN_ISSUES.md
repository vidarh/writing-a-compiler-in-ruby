# Known Issues

**Last Updated**: 2026-07-04

## Current State

Current spec numbers live in the auto-generated **[spec_status.md](spec_status.md)**
(refreshed by every sweep; do not copy numbers here — they rot). Snapshot at last
update: PASS 342 / FAIL 1797 / CRASH 10 / COMPILE_FAIL 5 / TIMEOUT 4 files;
5,935 individual tests passing.

Selftest: `make selftest` and `make selftest-c` both green (hard commit gate).

Resolved bugs and their full investigation logs are archived in
**[bugs/RESOLVED_INVESTIGATIONS.md](bugs/RESOLVED_INVESTIGATIONS.md)** (break-target
semantics, env/`__tmp_proc` slot aliasing, the two eigenclass heap-corruption
mechanisms, singleton_class-on-immediates, and the shunting-yard index-precedence
bug). The 2026-07 review lives in **[review/ANALYSIS.md](review/ANALYSIS.md)** with
a full failure triage and ranked plan.

---

## Active Issues

### 1. Live bugs found by the 2026-07-04 review (see review/ANALYSIS.md)

- ~~`def f(a = 1); body; ensure; cleanup; end` crashes at runtime~~ — FIXED
  `67f79f4` (R1 `normalize_body_shape`; repros test/repros/de1.rb, de2.rb).
- ~~`a, b = recv&.m, v` / `f x&.m, v` parse mangled~~ — FIXED (R4 step 1:
  dot-comma normalization extended to `:safe_callm`; repros test/repros/sc1.rb,
  sc2.rb). MLHS safe-nav (`s&.x, c = ...`) is a SyntaxError in MRI.
- **Op-assign of an env-captured target inside a block leaks a raw AST
  s-expression into a constant scope name** (`uninitialized constant
  [:index,[:index,:__env__,1],3]::A`) — language/assignments_spec.
- **Stabby lambda with rest-args whose body creates a nested proc**: `__tmp_proc`
  not declared in the lambda's let → `undefined method '__tmp_proc'`. Gates 253
  fails in file/printf_spec and the shared :kernel_sprintf suite.
- **`Array.[]` / subclass instantiation (`MyArray[...]`)**: CONFIRMED and
  pinned 2026-07-05 (see 3c below and lib/core/array.rb) — both unconditional
  and subclass-guarded `__new` bypasses segfault stage-1 self-compilation.
  The `Array.new(other_array)` copy half IS fixed (8eb49b4).
- **`__get_raw` unreachable on Array subclasses** (variables_spec destructuring).

### 2. Pattern binding inside a block is not env-captured (exposed 2026-07-04)

`rewrite_pattern_matching` runs AFTER `find_vars` (documented at transform.rb:19–22),
so a pattern-bound variable (`in [a, 1] if a >= 0`) referenced inside an it-block/
closure resolves as a method call → "undefined method 'a'". In
language/pattern_matching_spec the raise then crashes the exception-print path
(same containment-escape family as issue 3 below), flipping the whole file
FAIL→CRASH now that its `Warning` before-hook no longer aborts every test.
Fix: capture pattern bindings (run the rewrite before find_vars, or register its
lvars) — see also refactoring item R5 (pass manifest).

### 3. Exception containment escape on runtime-redefined method raise (test/repros/st5.rb)

When a method redefined at runtime via alias + def-in-block (e.g.
`Integer#<=>` := raise) raises, the exception escapes the spec harness's
it-rescue entirely and aborts the file. Behind core/array/sort_spec's abort and
the pattern_matching crash above. 18-line repro: test/repros/st5.rb.

### 3b. Forwarded `&nil` fools block_given?/yield (2026-07-04)

`f(*a, &b)` with b == nil puts the nil OBJECT (a nonzero pointer) in the block
slot; MRI treats `&nil` as "no block", but `block_given?` and the yield guard
test only `!= 0`, so the callee tries `nil.call`. An explicit `&blk` PARAM is
immune (its binding reads back as nil — `blk.nil?` is correct), so the
convention for delegation targets is: use `&blk` + `blk.nil?`/`blk.call`, not
block_given?/yield (File.open, IO.popen converted). Three compiler-side fixes
all broke bootstrap-critical paths and were reverted — do NOT retry without
reading the failure notes: (a) wrapping the to_block call-site arg in a
`__block_arg` call corrupted `Class#new`'s splat marshalling; (b) an inline
`[:and, [:ne,..,0], [:ne,..,:nil]]` guard MISCOMPILED self-hosted (eigenclass
yields emitted garbage asm); (c) a prologue sexp normalizing the `__closure__`
arg slot crashed stage-1 with SIGFPE. The eventual fix probably needs (b)
root-caused first — it is the cleanest design and its miscompile is a compiler
bug in its own right.

### 3c. Loop-carried locals go stale in call-rich loop bodies (2026-07-05) — COMPILER BUG, pinned

Locals reassigned each iteration from array reads (`item = queue[qi]`) in a
while body containing calls read STALE values across those calls — two
divergent storage locations for the same local (an instrumented run printed
the PREVIOUS item's value from interpolation while the calls used the current
one). Workarounds in tree: Dir.glob's queue walk (lib/core/glob.rb, per-item
method frames + inline indexing), Enumerator::Product (ivars),
Set in-place filters (in-loop change flags), String#__copy_raw (derive before
bindex). RELATED, same family: adding ANY extra branch to Array.[] segfaults or
fails stage-1 self-compilation — THREE variants confirmed 2026-07-05:
unconditional __new, Ruby-guarded (`if self.equal?(Array)`), and a raw
`%s(if (eq self Array) ...)` sexp branch. The guard never fires self-hosted,
so this is purely shape/layout-sensitive miscompilation of Array.[] (the
hottest bootstrap function). CRASH SIGNATURE (gdb, ASLR off, raw-sexp
variant): stage-1 dies in __method_Compiler_compile_eval_arg dispatching on
%esi == 0 (`mov (%esi),%eax; call *0x3c(%eax)`) deep in a compile recursion
through send/__send_for_obj__ — i.e. the modified Array.[] intermittently
returns RAW 0 (not nil) under compiler-scale load and the null array flows
until method dispatch. Small programs pass; the failure is state/pressure
dependent. Start the hunt by diffing the MRI-hosted asm of Array.[] with and
without the branch and auditing the sexp-if result/assign paths for a code
path that leaves `a`'s slot holding 0. That single bug gates ~40 MyArray
specs (slice_spec measured 9→52 with the bypass). Highest-leverage compiler
hunt right now.

### 4. Keyword arguments — correctness gaps (~85 tests, one workstream)

Basic kwargs work (required/optional/`**rest`). Wrong: kw-vs-positional-hash
split, `super` drops all kwargs (29 super_spec fails), `**nil`/`**{}` mishandled,
arity errors with post-splat+kwarg params. keyword_arguments_spec no longer
crashes — it fails 26 tests. Triage cluster C6 in review/triage-language.md.

### 5. Deferred crash-adjacent findings (2026-07-01)

Root-caused but intentionally not yet fixed:

- **`for` loop variable does not leak** (Ruby: stays visible after the loop;
  here block-scoped, so `for i in 1..3; end; p i` raises).
- **Op-assign on a hash index with a boolean-literal key miscompiles.**
  `h[true] ||= []` fails with "undefined method 'true'" — the boolean literal in
  the index position of an op-assign is treated as a method call. Plain
  `h[true] = x` and `h[:sym] ||= x` work.
- **`class E` (or any name colliding with a leaked runtime constant) segfaults.**
  The compiler's `E = Expr` AST alias leaks into every compiled program's
  namespace via `E = 2` in lib/core/stubs.rb. Real fix: stop the compiler's
  internal alias leaking into the runtime constant namespace (architectural).
- **core/string/scan_spec.rb hangs the compiler** (infinite loop at compile
  time; no single extracted construct reproduces). Masked by COMPILE_TIMEOUT in
  run_rubyspec (surfaces as COMPILE_FAIL). Needs bisection of the preprocessed file.
- **language/ensure_spec.rb: compile-time infinite recursion** (2026-07-04) —
  SystemStackError, ~8.7k frames cycling through compile_exp/compile_sexp
  (funcscope get_arg). NOT the (fixed) bare-block body-shape bug. Needs
  bisection of the preprocessed file.

### 6. `Array#initialize` — `send` edge cases

Direct forms work (`Array.new(3)`, `(3, :x)`, `(3){ }` — commit d7bcf70). Still
broken: `x.send(:initialize, ...)` — send's splat dispatch miscounts `numargs`,
so the size/copy branch reads garbage → segfault. Needs the arg count via a RAW
read of `__copysplat`'s length slot (Ruby-level `.length`/`is_a?` in that
bootstrap path segfault the direct forms), or a fix to `send`/`__send_for_obj__`
numargs under splat dispatch. Also `Array.new([1,2,3])` raises
`undefined method '__get_raw'` (should be TypeError).

### 7. Instance-variable reflection unimplemented

`instance_variable_get/_set/_defined?`/`instance_variables` don't exist and
CANNOT be pure-library: ivars get fixed compile-time slot offsets
(`ClassScope#find_ivar_offset`) and no name→offset map is emitted at runtime.
Proper fix: emit a per-class ivar-name→offset table (mirroring the vtable).
Very common mspec idiom (all attr_writer/attr_accessor specs).

### 8. `class << x` and `x.singleton_class` create DISTINCT metaclasses

compile_eigenclass (compile-time) and Object#singleton_class (runtime) each
allocate a fresh metaclass and overwrite slot 0; Ruby returns the same object.
Also frozen-state is not tracked (a frozen object's singleton isn't frozen).
Remaining feature gap from the (fixed) singleton_class-on-immediates crash.

### 9. core/basicobject/singleton_method_added_spec — segfault (OPEN, resists minimal repro)

A Proc with corrupted `@addr` (points at the read-only string "Object") is
invoked from the FIRST it block's should/matcher plumbing. Only the full harness
run triggers it; every extracted construct survives in isolation. Pre-existing
(not a regression from the eigenclass fixes). Needs ASLR-off gdb + watchpoint on
the real temp binary. Note: the `singleton_method_added` HOOK is also
unimplemented (feature gap, separate from the crash).

### 10. Compound expression after if/else (UNVERIFIED, 2025-era)

`result = obj.method1 + obj.method2` immediately after an if/else block was
reported to corrupt variables. Not re-verified against the current compiler —
re-test before investing; may be long fixed (several parser/regalloc fixes have
landed since).

---

## Known Limitations (architectural / project-scale)

1. **eval() with dynamic strings** — AOT compilation cannot evaluate runtime
   strings. (SyntaxError-expectation specs are wontfix-ish for the same reason.)
2. **Float — entirely stubbed.** Arithmetic returns self, comparisons broken.
   The single biggest blocker (~2,300+ assertions + 4 of the 10 remaining CRASH
   files). Dedicated project; see review/ANALYSIS.md.
3. **Threads/Fibers** — no runtime; Thread.current is a stub. (~1,050 assertions.)
4. **Marshal** — by-design NotImplementedError (1,339 assertions).
5. **Command execution** — backticks/`%x{}` not implemented.
6. **Encodings** — stubs; byte-oriented runtime.
7. **Pattern matching `case/in`** — partial (literal/array patterns and guards
   run); full deconstruct/deconstruct_keys/pin/find patterns are a parser +
   pattern-compiler project (222 tests). See also Active issue 2.

Fixed and removed from this list (2026-07-04): a block/proc's own block
parameter `proc { |&b| }` — the dedicated call-block ABI slot (`__callblk__`)
shipped in 63b5875; `break` now MRI-correct via nested closure environments
(c6d1f4f).

---

## Test Framework Notes (rubyspec_helper.rb)

Implemented: ScratchPad, fixture inlining (run_rubyspec), exception rescue
around examples AND before-blocks/describe bodies, complain/have_method/
have_instance_method/have_constant/be_ancestor_of/be_computed_by matchers,
with_timezone, Warning category flags, Mock/MockExpectationStub chains.

Real remaining gaps:
- `require $spec_filename`-style dynamic require — not supported (AOT).
- Mock#should_receive does not actually REGISTER an expectation (sets
  @call_counts but not @expectations), so mocked calls without and_return hit
  method_missing and return nil; call counts are not enforced.
- `ruby_cmd`/`ruby_exe` — no subprocess re-invocation of specs.

---

## References

- **[review/ANALYSIS.md](review/ANALYSIS.md)** — 2026-07-04 full review: cleanup,
  refactoring (R1–R12), docs, failure triage & ranked plan
- **[spec_status.md](spec_status.md)** — auto-generated current spec results
- **[bugs/RESOLVED_INVESTIGATIONS.md](bugs/RESOLVED_INVESTIGATIONS.md)** — archived fixed-bug investigations
- **TODO.md** — prioritized task list
- **DEBUGGING_GUIDE.md** — debugging techniques
