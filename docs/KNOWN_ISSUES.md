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

### 2b. Implicit block-argument auto-splat is not performed (2026-07-05)

When a block declares multiple parameters but the yielder passes a SINGLE array
argument, Ruby auto-splats the array across the parameters:
`[[1,2],[3,4]].map {|x,y| x+y }` binds x=1,y=2. We do not: the whole `[1,2]`
lands in the first parameter (`select {|x,y| x>1}` fails with "undefined method
'>' for [1,2]"), and `map`/`each` over pairs crash inconsistently ("undefined
method 'each' for nil", one element succeeding then the next aborting — smells
like a codegen/register issue in the partial handling). EXPLICIT destructuring
works: `{|(x,y)| ... }` binds correctly (transform.rb `:destruct` params, ~440),
and native two-value yielders are fine (`Hash#each`/`min_by`/`merge` with
`{|k,v| }` all pass). So the gap is specifically implicit single-array →
multi-param splat in the block prologue. Compiler-level (block parameter binding),
not a lib fix — high value (hits `arr_of_pairs.map {|a,b| }`, a very common form).
NOTE (2026-07-05): `Hash#map`/`collect`/`each_with_object`/`reduce` were since
added (they yield the two values natively, so `{|k,v| }` needs no splat); the
splat gap only affects the rarer one-parameter block over already-paired
elements (`arr_of_pairs.map {|pair| }` still binds pair=first-element, and a
Hash enumerator's `.map {|pair,i| }` mis-binds). Still compiler-level.

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

### 3d. Splat + side-effecting block-pass mis-marshals (2026-07-05)

`m(*a, 2, &a.pop)` where the block-pass argument MUTATES the same array
being splatted evaluates out of source order: MRI materializes `*a` first
then evaluates `&a.pop`, but here the block arg is evaluated interleaved,
so the splat array captures garbage (`m(*[1,9],2,&c.pop)` gave
`[[1,2,<garbage>],9]` instead of MRI's TypeError / the nil-pop no-block
case's `[[1,nil,2],nil]`). Returns garbage in isolation; CRASHES in a full
spec run when the garbage pointer is later dereferenced. Pre-existing
(confirmed by stashing the module_function change); now REACHED by
language/send_spec once module_function un-gates its earlier tests
(send_spec: was FAIL 10p, now CRASH at the `m(*args,2,&args.pop)` test).
Deep in compile_callm splat+block arg ordering; pathological shape.

### 3e. Module-body local miscompiles as a method call at scale (2026-07-05)

In a LARGE module body, a plain local variable read resolves as a method
call on the module instead of the local. The core/module fixture
(rubyspec/core/module/fixtures/classes.rb, 653 lines) does
`m = Module.new do..end` then `EmptyFooMethod = m.instance_method(:foo)`;
at runtime `m` dispatches as `ModuleSpecs.m` -> "undefined method 'm' for
ModuleSpecs", crashing all 61 module specs that load this fixture (the
single biggest failure cluster). LOADS FINE standalone (the 653-line fixture minus requires runs to
completion), a MINIMAL repro works, but fixture + full spec CRASHES.
RULED OUT (2026-07-05 experiments): NOT pure size -- a 1000-dummy-method
program AND a 600-method module body BOTH containing the exact
`m = Module.new{} + m.instance_method` pattern compile and run FINE. So
the trigger is a SPECIFIC CONSTRUCT COMBINATION in the fixture (it has
module_function, nested modules, `class << self`, alias, private, class
vars), not line count. LAYOUT/ASLR-SENSITIVE: under `setarch -R` (ASLR off) the crashing binary
exits cleanly (0 tests, no segfault) instead of dying -- so a deterministic
repro needs the ASLR-off + valgrind/watchpoint tooling from the crash-
burndown era, not simple bisection (5+ construct-repro attempts and the
full fixture-minus-requires all fail to trigger it in isolation). A
dedicated debugging session, not a loop-tick fix, the same family as the other layout-sensitive
miscompiles (glob loop-carried locals, Array.[] extra-branch,
b94260b module-override). Fixing needs module-body local-scope analysis
under scale; do NOT attempt without a scale repro and the full gate
ladder. Highest-count actionable compiler bug in the burndown.

### 3h. `class <Name> < <localvar>` — a runtime superclass — FIXED (2026-07-06)

FIXED: a lowercase-initial symbol superclass (always a local/method, never a
constant) is now routed through the existing `__superclass__` expression path
(evaluated at runtime) instead of being referenced as a static global symbol. One
targeted change in compile_class.rb (the `local_super` flag). All three specs now
COMPILE and run (core/class/inherited_spec, language/class_spec +15 passing,
core/module/const_added_spec) -- COMPILE_FAIL 4->1. Safe: a strict no-op for every
other superclass form (constant / absent / expression); make selftest + selftest-c
Fails:0, crash battery 102/102, and the class+module+language sweep added no new
crasher (alias_spec/defined_spec were already deterministic crashers at baseline
in isolation -- their parallel FAIL-vs-CRASH classification is flaky, not a
regression). Guarded by test/repros/battery/class_local_superclass.rb. Original
report retained below.

`class Foo < parent` where `parent` is a LOCAL variable (holding a class) fails.
Three deterministic COMPILE_FAILs hit this -- core/class/inherited_spec (line 114
`class parent::C < parent`), language/class_spec, core/module/const_added_spec.

PRECISELY ISOLATED (2026-07-05, correcting an earlier wrong guess): it is the
SUPERCLASS, not the namespace. `class parent::C` (namespace base a local) compiles
fine on its own; `class Foo < parent` (constant name, LOCAL superclass) is the
failing part:
- at TOP LEVEL it compiles but silently resolves the superclass to Object
  (`Foo.superclass == parent` is false) -- wrong but no crash;
- inside a BLOCK it emits `parent` as an undefined global symbol -> link error
  `undefined reference to 'parent'`.
Root cause: `compile_class` (compile_class.rb:371) only resolves a superclass from
the COMPILE-TIME `@classes` registry (`@classes[superclass]`) plus a qualified-name
retry; a superclass that is a runtime local variable is never found, so it both
mis-resolves to Object AND (in a block) references the uncaptured local as a global.
NB `Class.new(parent)` works -- the gap is specifically the `class X < Y` keyword
form with a runtime `Y`.

Proper fix needs RUNTIME superclass evaluation: emit code that evaluates the
superclass expression and creates the class with that class object at runtime
(instead of statically wiring the vtable/parent from @classes). That is a real
compiler feature touching class-creation codegen -- do NOT attempt piecemeal.
Two prior guesses (compile_class name-flattening; find_vars class-name capture)
were both ineffective and reverted; they targeted the namespace, which is not the
bug. A minimal partial win MIGHT be: make the block case merely COMPILE (capture
the superclass local so it is not an undefined symbol) to turn COMPILE_FAIL into a
runtime FAIL -- but verify it does not become a CRASH first.

### 3f. Anonymous classes not named by constant assignment (2026-07-05)

`Anon = Class.new` (and `D = Data.define(...)`, `S = Struct.new(:a)` without a
string name) leaves the class's @name inherited ("Object"/"Struct") instead of
MRI's "Anon"/"D"/"S". MRI names an anonymous class after the FIRST constant it
is assigned to; we do not track that. Top-level `CONST = <class>` is a
compile-time addr assignment (not the runtime __const_set_global path), so it
cannot be hooked in lib -- it needs a compiler change in compile_assign to
detect a class-valued constant assignment and set the class @name to the
constant name at runtime. ONE root cause behind several inspect/name spec
failures (Struct/Data/anonymous Class/Module). Cosmetic-ish (mostly #inspect
and #name strings); deferred as a compiler feature. Struct.new("Name",...)
IS named correctly (explicit string arg, 19aae43).

### 3g. Bignum multiplication produces wrong digits for large operands (2026-07-05) — COMPILER/LIB BUG, pinned

Multiplying two large bignums gives an incorrect result once the operands exceed
~30 decimal digits, even though smaller bignums are exact:

    5 ** 50            # CORRECT: 88817841970012523233890533447265625
    a = 5 ** 50; a * a # WRONG:  ...210124184099449116383295730... (MRI ...210118054117285652827862296...)
    5 ** 100           # WRONG (a third, different wrong value — ** path diverges from a*a path)
    2 ** 64            # CORRECT: 18446744073709551616

So `2**64` and `5**50` are exact but `(5**50)*(5**50)` is not — the defect is in
the large-operand multiply (carry/limb handling in the bignum `*` routine, likely
the `%s(...)` sexp path in lib/core/integer.rb or the bignum representation), and
`**` (repeated-squaring) surfaces it too. Latent — most specs never build numbers
this large — but a genuine correctness bug.

**The divergence is DATA-dependent, not size-dependent** (bisected 2026-07-05):
EVERY power of two squared is correct up to 2^128 (single-bit operands exert no
carry pressure), while among powers of three `3^40 * 3^40` is WRONG but
`3^50 * 3^50` is CORRECT — non-monotonic in size. That rules out a simple
"limb-count threshold" and points to a carry-propagation bug that fires only for
particular limb-value patterns. NOT a loop-tick fix (a wrong patch corrupts ALL
arithmetic): needs a dedicated session that isolates the exact limb inputs of a
failing product (e.g. dump the limb arrays of `3^40` and multiply them by hand
against the routine) and audits the carry loop. `3^40 * 3^40 != 3^80` is a compact
starting repro.

**Partially investigated (2026-07-05):** the defect is in
`Integer#__multiply_heap_by_heap` (lib/core/integer.rb ~903), a hand-rolled
school multiplication over 30-bit limbs (limb base 2^30). Two carry injections
there use a RAW `+` without limb-overflow propagation (line ~976 adding
`product_carry_high`, line ~1002 adding `1`), unlike the main accumulation which
uses `__add_two_limbs_with_overflow`. Those raw `+`s ARE latent bugs, BUT fixing
them (routing through a carry-propagating `__add_carry_into` helper) AND adding a
final limb-normalization sweep does **NOT** fix the symptom — verified: `3^40 * 3^40`
still diverges. So the raw-`+` injections are not the (whole) root cause.

Sharper clue: **multiplication is not commutative** for the failing operands
(`(11**29) * x != x * (11**29)`), and `__multiply_heap_by_heap` is asymmetric
(outer loop over `other`'s limbs, inner over `self`'s). That points the finger at
the per-limb step `__multiply_limb_by_fixnum_with_carry` (its carry-out math at
lines ~787-799: the `sum_high*4 + (sum_low>>30)` reconstruction and the
`sign_adjust` for negative `sum_low`) or the main accumulation carry logic
(~947-980), not the two injection points. `60!` (a fixnum-accumulation path,
`__multiply_heap_by_fixnum`) is CORRECT, so the fixnum path is fine — only
heap*heap is broken. Next session: instrument `__multiply_limb_by_fixnum_with_carry`
with a differential against `limb*fixnum+carry` computed in plain Ruby over the
actual limb values of `3^40`, and check the carry-out reconstruction.

### 4. Keyword arguments — correctness gaps (~85 tests, one workstream)

Basic kwargs work (required/optional/`**rest`). Wrong: kw-vs-positional-hash
split, `super` drops all kwargs (29 super_spec fails), `**nil`/`**{}` mishandled,
arity errors with post-splat+kwarg params. keyword_arguments_spec no longer
crashes — it fails 26 tests.

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

## Binary-unsafe string literals (embedded NUL truncates length)

String LITERALS with an embedded `\x00` get the wrong length: `"\x00".length` -> 0,
`"a\x00b".length` -> 1. The String class itself is binary-safe (stores raw `@length`),
but the C-string constructor used for literals (`lib/core/string.rb` ~line 385,
`%s(assign @length (strlen @buffer))`) computes length via `strlen`, which stops at
the first NUL. Fix requires the emitter (`emitter.rb` `:strconst`, ~line 195) to pass
each literal's compile-time-known byte count to a length-taking constructor instead of
relying on strlen. Deep codegen change touching every string literal; low impact
(only NUL-containing literals, e.g. core/string/empty_spec's `"\x00"`). Verified 2026-07-09.
