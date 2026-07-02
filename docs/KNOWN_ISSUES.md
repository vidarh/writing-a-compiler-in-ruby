# Known Issues

**Last Updated**: 2026-02-10

## Current State Summary

**Selftest**: All passing (selftest and selftest-c)

**Language Specs**: 78 files
- Passed: 3 files (and_spec, not_spec, unless_spec)
- Failed: 28 files (run but fail assertions)
- Crashed: 47 files (segfaults/hangs)
- Compile fail: 0 files (all specs compile)

**Individual Test Cases**: 994 total, 272 passed, 705 failed, 17 skipped, 27% pass rate

## Recent Fixes (2025-12-01)

1. **Break from blocks crash** - Top-level blocks with `break` no longer crash
   - Root cause: After unwinding stack frames, %ebx was restored from wrong frame
   - Fix: Save %ebx to %edx before unwinding loop, restore after
   - Note: Break still exits DEFINER instead of YIELDER (not Ruby-compliant)

2. **Super in deep hierarchies** - `super` now works correctly in A < B < C chains
   - Root cause: Was using `self.class.superclass` instead of defining class's superclass
   - Fix: Pass defining class name and look up its superclass directly
   - Remaining edge case: `super()` in `define_method` blocks still unsupported (needs method name from define_method arg)

3. **Hash with nil keys** - `{nil => value}[nil]` now works correctly
   - Root cause: nil was used as both valid key AND empty slot marker
   - Fix: Added special handling to iterate/lookup nil keys via linked list

4. **Classes in lambdas** - Simple classes defined inside lambdas now compile and run correctly

## Previous Fixes (2025-11-30)

1. **Array#<< growth condition** (ba819c8) - Fixed inverted condition that caused memory exhaustion
2. **Postfix if/unless returns nil** (2dee682) - `(x if false)` now returns nil, not false
3. **Parallel assignment** (cbd40e0) - `a, b, c = 1, 2, 3` now works correctly
4. **Scope resolution (::) as prefix** (17eab49) - `::Object` now works after whitespace
5. **Block params with defaults** (8ccfcbd) - `{ |a=99| }` correctly applies defaults
6. **Break/next newline handling** (8c97401) - `break\nputs x` now parses as two statements
7. **Hash spread operator (**)** - `{**h, a: 1}` now parses correctly (was exponentiation)

---

## Active Issues

### 0. `expr OP arr[i].method` mis-parsed — trailing method bound to the whole operator expression (FIXED)

**Status**: FIXED (shunting.rb). Was originally mis-diagnosed as a codegen/register bug; it is a parser
precedence bug in the shunting yard.

**Symptom**: When the right operand of a binary operator was an indexed method call (`arr[i].meth`), the
trailing `.meth` bound to the entire operator expression instead of to `arr[i]`:

```ruby
a + b[1].c                       #  parsed as  (a + b[1]).c    (want  a + (b[1].c))
v[0].inspect + v[1].inspect      #  parsed as  (v[0].inspect + v[1]).inspect
```

**Root cause**: After parsing an index subscript, the just-pushed `#index#` operator (pri 100) was fired
via `reduce(@ostack, @opcall2)`. `#call2#` has priority **9**, and `reduce` pops every operator whose
`right_pri > pri`, so it also popped a pending lower-priority infix (e.g. `+`, pri 14) — reducing the
`+` before the following `.method` arrived, which then attached to the reduced result.

**Fix**: When the pushed operator is `#index#`, fire it directly (`@out.oper(@ostack.pop)`) instead of
going through the pri-9 reduce, so only the index binds and pending lower-priority infix operators are
left untouched. Chained `a[1][2]`, index assignment `a[1] = 2` (→ `[]=`), and paren-less `foo bar[1]`
all still parse correctly. Both gates green.

### 1. Break from Blocks - Wrong Return Target (Partial)

**Status**: No longer crashes, but semantics are not Ruby-compliant

**2025-12-01 Update**: Resolved crash when break is called from top-level blocks.
The issue was that after unwinding stack frames, %ebx was being restored from
the wrong frame (target frame instead of source frame). Solution: Save %ebx to %edx
before the unwinding loop, restore after.

**Remaining Issue**: `break` behaves like `return` - exits the DEFINER instead of the YIELDER.

In Ruby:
- `break` should exit the method that YIELDED to the block
- `return` should exit the method that DEFINED the block
- Current implementation has `break` behaving like `return`

**Example of wrong behavior**:
```ruby
def yielder
  yield
  puts "after yield"  # MRI: does NOT print (break exits yielder)
end

def test
  yielder { break }
  puts "after yielder"  # MRI: prints this
end
test
# MRI output: "after yielder"
# Our output: nothing (exits test entirely because break acts like return)
```

**Root Cause**:
- Blocks capture `__env__[0]` = frame pointer where block was CREATED
- `break` unwinds to `__env__[0]` which is the CREATOR's frame
- Should unwind to YIELDER's frame instead

**What works**:
- `return` from blocks (correctly returns from defining method)
- `break` inside `while`/`until` loops (uses ControlScope, not __env__)
- Break no longer crashes (resolved 2025-12-01)

**What doesn't work correctly**:
- `break` exits the definer instead of the yielder (wrong Ruby semantics)

**Previous fix attempts** (documented for reference):

1. **Two-slot env approach** (self-compilation crashes):
   - Add `__breakframe__` at `__env__[1]`, keep `__stackframe__` at `__env__[0]`
   - `Proc#call` sets `@env[1]` to `caller_stackframe` before calling block
   - Break reads `__env__[1]` instead of `__env__[0]`
   - **BLOCKED**: Self-compilation crashes due to env layout change

2. **Global variable approach** (crashes):
   - Store break target in global variable, set by `Proc#call`
   - Causes crashes for unknown reasons

**Affected specs**: block_spec, lambda_spec, proc_spec, loop_spec, and others

---

### 2. Keyword Arguments - Partial Support

**Status**: Basic keyword args work, advanced features segfault

**Works**:
- `def foo(a:, b:)` - required kwargs
- `def foo(a: 42)` - optional kwargs
- `def foo(**kwargs)` - keyword rest

**Doesn't work**: keyword_arguments_spec still crashes

---

### 3. Compound Expression After If/Else

**Problem**: Compound expressions immediately after if/else can corrupt variables.

```ruby
if condition
  # branch
end
result = obj.method1 + obj.method2  # May crash
```

**Workaround**: Break into separate statements.

---

### 4. Deferred crash-adjacent findings (2026-07-01)

Root-caused but intentionally not yet fixed (need larger features / deeper semantics work):

- **`for` loop variable does not leak.** In Ruby a `for i in ...` variable stays visible after the loop;
  here it is block-scoped, so `for i in 1..3; end; p i` raises "undefined method 'i'".
- **Op-assign on a hash index with a boolean-literal key miscompiles.** `h[true] ||= []` (and
  presumably `h[false] ||= ...` / other op-assigns) fails at runtime with "undefined method 'true'" --
  the `true`/`false` literal in the index position of an op-assign is treated as a method call. Plain
  `h[true] = x` / `h[true]` and `h[:sym] ||= x` all work, so it is specific to a boolean literal as the
  index of an op-assign. Workaround: expand to an explicit nil-check (see Array#group_by).
- **`|&block|` (block param of a block/lambda) is unbound.** `rewrite_lambda` leaves it as an
  uninitialised positional defun param, and `block_given?`/`__closure__` inside a yielded-to block do not
  reflect a block passed to the block, so `{ |&b| b }` reads garbage. Binding it to
  `block_given? ? __closure__ : nil` (mirroring methods) does not help until block-to-block `block_given?`
  semantics are correct — reverted pending that.
- **Defining `class E` (and any name that collides with a leaked runtime constant) segfaults.** The
  compiler aliases its AST-node builder as `E = Expr` (ast.rb) and uses `E[...]` pervasively; the
  self-hosted build depends on `E = 2` in lib/core/stubs.rb to define that global slot. Because that
  `E = 2` lives in the runtime library, it also leaks into every compiled *user* program's namespace, so
  a program (or spec fixture) that does `class E ... end` collides with the existing Integer constant and
  segfaults during the class definition. Removing `E = 2` fixes user `class E` but breaks selftest-c
  ("uninitialized constant E"), so it cannot simply be deleted -- the real fix is to stop the compiler's
  internal `E`/`Expr` alias from leaking into the runtime constant namespace (an architectural change).
  CORRECTION (2026-07-02): an earlier revision of this file claimed a "re-raise / unwind bug" (that
  raising again from inside a rescue body segfaults). That was WRONG -- it was an artifact of the test
  programs using `class E`. Re-raise works correctly: `begin raise MyErr rescue => e; raise e end` and
  bare `raise` (which Kernel#raise now re-raises as `$!`) both propagate correctly to an enclosing
  rescue, across method boundaries, verified with a non-colliding class name.
- **`core/string/scan_spec.rb` hangs the *compiler* (infinite loop at compile time).** Compiling the
  preprocessed spec loops forever (confirmed: `./compile` on the temp file never returns; killed at
  50min during a sweep). The whole file hangs but no single construct extracted from it reproduces in
  isolation (tested empty regex `//`, `[[""]]*n`, multibyte string literals, `\G` anchors, `(...)`
  capture groups, and `|*w|`/multi-arg block params — all compile fine alone), so it is a combination /
  parser-state interaction, not one token. Now masked by the compile timeout added to run_rubyspec
  (COMPILE_TIMEOUT, default 120s -> COMPILE_FAIL) so it no longer stalls sweeps. Root-causing the parser
  loop needs a proper bisection of the preprocessed file.

---

### 5. Heap corruption gating the core/kernel cluster (2026-07-01) — FIXED 2026-07-02

FIXED in commit "Fix #5: ModuleScope#lvaroffset must delegate to the enclosing local scope". It was
NOT heap corruption at all: `ModuleScope`/`ClassScope` inherited `Scope#lvaroffset == 0`, so a
class/module body compiled inline in an enclosing frame allocated its locals overlapping the enclosing
`let`'s slots -- the body's `__tmp_proc` landed on the enclosing `__env__` slot, so building a
block/proc inside the body stored the lambda's code address into `__env__`, and later `__env__` uses
dereferenced a `.text` address (surfacing as the malloc/free "invalid next size" aborts and SIGSEGVs).
The ~68 crashing core/kernel specs now run instead of crashing. The one-line fix: delegate
`ModuleScope#lvaroffset` to `@local_scope` (mirroring `EigenclassScope`). The full historical
investigation is kept below for reference.

Most core/kernel specs abort with `free(): invalid next size (fast)` / `malloc(): invalid size` —
heap corruption surfaced by tgc's sweep at program exit (`tgc_sweep`, tgc.c:309). Some object is
allocated too small and a later write runs past it, clobbering the adjacent chunk's size header.

Narrowed repro (needs ALL of it — none of the parts corrupt alone):
- `require 'rubyspec_helper'` + the FULL `core/kernel/fixtures/classes.rb` (558 lines) loaded, then
  `KernelSpecs::A.new` **inside a block** (`[1].each { KernelSpecs::A.new }`). At top level or inside a
  plain method it does NOT corrupt; a plain class, or class A in isolation (even with its full
  undef_method/define_method/visibility body + subclass + reopen), does NOT corrupt. So it is a
  global-state interaction across the whole fixture + the block/env allocation path, not any single class.

Deeper findings (2026-07-01, instrumented tgc_sweep with an fprintf of every freed ptr/size/klass):
- It is a GENUINE heap overflow/bad-chunk, NOT a double-free. Over a run tgc_sweep fires ~25 times
  (GC cycles as the ~21k lib-init objects churn — a trivial `p 1` also allocates/frees ~21k and does
  NOT crash). Freed *addresses* repeat across sweeps only because malloc validly reuses an address for
  a new object after the old one is collected; per-sweep the free list is unique. So earlier
  "5809 unique / 21447 frees" is normal address reuse, not the bug.
- Over-allocating EVERY object by 256 bytes in `__alloc` (base.rb) did NOT prevent the crash — so it is
  not a small contiguous overflow into the next chunk; likely a wild write to a computed/out-of-bounds
  offset, or corruption of tgc's own `gc.items` table.
- Build note for instrumenting tgc: `./compile`'s LOCAL toolchain can't compile tgc.c (no 32-bit stdio
  headers under toolchain/32root), but the docker buildenv can:
  `docker run --rm -v "$PWD":/app -w /app ruby-compiler-buildenv gcc -Wall -c -m32 -o out/tgc.o tgc.c`.
  Pre-build out/tgc.o that way, then `./compile` (local) reuses it (it only rebuilds tgc.o when missing).
  This is also the path to try `-fsanitize=address` on tgc.c + libasan.so.5 (present in the 32root).

Next step: ASAN on the whole binary (the generated asm is not instrumented, so ASAN mainly helps via
its allocator redzones + allocation-site report at the faulting free) — or a canary/redzone check added
directly in tgc around each tracked object during mark, printing the object whose guard is clobbered.

Fixing it should recover a large share of the ~64 core/kernel crashes (they all load this fixture).

Further findings (2026-07-02):
- The trigger is broader than KernelSpecs::A: with the full fixture loaded, `[1].each { Object.new }`
  (ANY object allocation inside a block) corrupts. `KernelSpecs::A.new` at TOP LEVEL does NOT. So the
  ingredients are: (fixture loaded) + (an allocation performed inside a block/closure).
- Bisecting the fixture: the corruption needs "enough" method definitions. Concretely, cutting the
  fixture at line 493 (before `WarnInNestedCall`) + a following `Struct.new(:v){ def to_int; v; end }`
  survives; adding ~8 more trivial methods (`def g1;1;end`...) before the Struct makes it crash. So the
  trigger correlates with the TOTAL number of distinct method names (= vtable size), not any one class.
  The `Struct.new`/`Class.new` (runtime class creation) also matters -- removing it made the same prefix
  survive.
- It is DETERMINISTIC per binary (the full-fixture repro crashes 6/6) but LAYOUT-sensitive: trivially
  different sources flip crash/no-crash, which is why the aggregate CRASH count in spec_status swings ~±30.
- Ruled OUT this round (none fixed the deterministic repro): sizing every compile-time class object to the
  final `__vtable_size` (compile_class.rb class_alloc_size); sizing eigenclasses to `__vtable_size`
  (compile_eigenclass eksize). Combined with the earlier "+256 bytes per __alloc didn't help", the
  overflow is NOT a small contiguous overrun of a class object, an eigenclass, or a generic __alloc
  object (__alloc_env routes through __alloc too). Most likely a WILD write to a computed offset (e.g. a
  vtable-offset used against a too-small object on some path not yet found) or corruption of tgc's own
  gc.items table. Minimal deterministic repro for future work: `require 'rubyspec_helper'` + the full
  kernel fixture + `[1].each { Object.new }`. valgrind is NOT installed here; ASAN via the docker
  buildenv (libasan.so.5 in 32root) is the most promising next tool.

Even further findings (2026-07-02, second pass):
- Padding EVERY `__alloc` by 4096 bytes (calloc size+4096, tgc_add records size) does NOT prevent the
  crash. This definitively rules out a contiguous overrun of any `__alloc`'d object (objects, arrays,
  closure envs -- __alloc_env routes through __alloc). The corruption is a wild write to a computed/far
  address, or of memory tgc allocates for itself (gc.items / gc.frees, via its own malloc/realloc), or a
  stack-frame corruption.
- Re-applying BOTH `class_alloc_size = __vtable_size` (compile_class) AND `eksize = __vtable_size`
  (compile_eigenclass) TOGETHER still does NOT fix the deterministic repro. So the overflow target is not
  an undersized class object / eigenclass reached via __set_vtable subclass propagation (a tempting
  hypothesis: __set_vtable writes p[off] into every subclass, and eigenclasses link as subclasses -- but
  sizing them all to __vtable_size did not help). Reverted.
- gdb on the deterministic repro: it SIGSEGVs (not the glibc free-abort seen in specs -- same root,
  different manifestation) at `mov %eax,(%edx)` where `edx` is loaded from a stack local (-0x14(%ebp))
  holding 0x566674a5 -- an ODD address, i.e. a tagged Fixnum being used as an object pointer (type
  confusion). So by the time the tail of the program runs, a stack local / value has been clobbered with
  a Fixnum-tagged word. Whether the primary corruption is heap (tgc metadata) or stack is still open.
  Next: a hardware watchpoint on the specific clobbered slot, or ASAN, to catch the first bad write.

ROOT CAUSE FOUND (2026-07-02, hardware watchpoint):
- A conditional hardware watchpoint on the clobbered stack slot caught the corrupting write. In the
  deterministic repro the slot is `-0x14(%ebp)` in `main`, which is the top-level `__env__` (set at
  `main+101` from `__alloc_env`). The write happens while compiling repro.rb:517
  (`CustomRangeInteger = Struct.new(:value) do ... end`): the emitted code is
  `mov $__lambda_L545, %eax ; mov %eax, -0x14(%ebp)` -- i.e. it stores the block's compiled lambda
  ADDRESS straight into the `__env__` slot, destroying the env pointer. (`info symbol 0x566686ad` ->
  `__lambda_L545`; the address is odd only because functions aren't alignment-padded.)
- After that, every one of main's ~1284 `__env__` references uses a .text code address as the env
  pointer -> wild reads/writes into read-only code and the heap -> the assorted downstream symptoms
  (SIGSEGV writing through it here; free()/malloc "invalid next size" in the specs). This is NOT a heap
  overflow at all -- it is a compiler stack-slot ALIASING bug: the temporary that holds a block
  argument's lambda address is allocated to the same frame slot as `__env__` when the enclosing scope
  has a closure env. That is why the trigger needs (a) a block-taking call like `Struct.new do..end`
  AND (b) an enclosing `__env__` (present because of the top-level `[1].each {}` block / the fixture's
  closures), and why it correlates loosely with code size (slot assignment shifts with surrounding code).
- FIX DIRECTION: block/proc-argument compilation must use a fresh temp for the lambda address, never the
  `__env__` slot. Look at how the block arg's lambda pointer is emitted+stored around compile_callm /
  the proc-literal path and the local/temp allocator (get_local) so it cannot collide with __env__.
- Fix attempts that did NOT work (2026-07-02): (a) inlining the `[:defun]` directly into the __new_proc
  args instead of via :__tmp_proc -- generates invalid asm ("invalid character '?'"), so the lambda
  address MUST go through a named local. (b) Broadening `class_body_creates_closure?` to also detect
  pre-rewrite :proc/:lambda/:block nodes -- still crashes. (c) Reordering the top-level let to
  `[:__tmp_proc, :__closure__, :__env__]` (separate env/tmp_proc) -- still crashes (the collision is not
  in the top-level main let). So the collision is a nested-scope OFFSET computation issue.

- Minimal deterministic repro checked in: `docs/bugs/env_tmpproc_collision_repro.rb` (~15 lines: a module
  with a few methods + a `Struct.new(:value) do..end` + `[1].each { Object.new }`). Crashes 3/3.

- Offset analysis via a debug print in `LocalVarScope#get_arg` (compiling the minimal repro): for a scope
  with `locals=[:__env__, :__tmp_proc]`, `__env__` resolves to `[:lvar, 1]` when the enclosing FuncScope's
  `lvaroffset` (== `Function#@defaultvars`) is 0, but `[:lvar, 2]` when it is 1; `__tmp_proc` resolves to
  `[:lvar, 2]` (defaultvars 0) / `[:lvar, 3]` (defaultvars 1). So `__env__` and `__tmp_proc` overlap at
  lvar 2 across the two cases. The offset is `@locals[a] + (rest? ? 1 : 0) + @next.lvaroffset`, and the
  `@next.lvaroffset` (a Function's optional-arg count) is being applied INCONSISTENTLY between where
  `__env__` is set up (via `__alloc_env`) and where it is later read at the proc-construction site --
  i.e. the same env storage is written at one %ebp slot and read at another, and the read lands on
  `__tmp_proc`. Note: `compile_class`'s class-body let already keeps env/tmp_proc non-adjacent (idx1 vs
  idx3) yet still collides, so the drift is >= 2 slots, not a simple off-by-one. THE FIX must make the
  `@defaultvars`/`lvaroffset` contribution consistent for a given frame's `__env__` between allocation
  and every access (localvarscope.rb `get_arg`/`lvaroffset` + funcscope/function `lvaroffset`), WITHOUT
  shifting the offsets of the code that currently works (both gates pass today). Verify with the checked-in
  repro + `make selftest selftest-c`.

---

### 6. `Array#initialize` unimplemented for size/fill/copy; bootstrap-sensitive (2026-07-02)

`Array.new` only works for the no-argument and (indirectly) some internal cases. Concretely:
- `Array.new(3)` → `[]` (should be `[nil, nil, nil]`)
- `Array.new(3, :x)` → `[]` (should be `[:x, :x, :x]`)
- `Array.new(3) { |i| i * 2 }` → `[]` (block ignored; should be `[0, 2, 4]`)
- `Array.new([1, 2, 3])` → raises `undefined method '__get_raw' for [1,2,3]` (the copy path is broken too)
- `[].send(:initialize, 3)` (one arg, no block, via `send`) → **segfault** (the `numargs`-based copy
  branch trips under `send`'s splat dispatch and reads an Integer as a raw array pointer).

The current stub (`def initialize *__copysplat; __initialize; %s(if (gt numargs 2) (callm self
__copy_init ((index __copysplat 0))))`) uses raw `%s` ops on `__copysplat` on purpose: `initialize` is
called for EVERY array creation including during early bootstrap, where `__copysplat` is NOT a usable
Ruby Array. A Ruby-level rewrite was attempted (use `__copysplat.length`/`[0]`, `&block`, fill via `<<`,
copy via `concat`) and it **segfaults even `Array.new` with no args** — adding a `&block` param and/or
calling `.length` on `__copysplat` breaks the `self.new`→`initialize` calling convention at bootstrap.

So a proper fix must inspect the arguments with raw `%s` primitives (arg count + per-arg raw reads)
rather than Ruby method calls, and only enter the fill/copy loops once the runtime is up. This is a
dedicated task; it is NOT a quick Ruby-level edit. Affects core/array/initialize_spec (crashes) plus any
spec relying on `Array.new(n)`/`Array.new(n, obj)` fill semantics.

---

### 7. `instance_variable_get`/`_set`/`_defined?`/`instance_variables` unimplemented (2026-07-02)

None of the instance-variable reflection methods exist, so specs that assert on ivars via
`o.instance_variable_get(:@foo)` (a very common mspec idiom, e.g. all the attr_writer/attr_accessor
specs) hit "undefined method 'instance_variable_get'" and abort.

They cannot be added as a pure-library method: instance variables are assigned FIXED slot offsets at
compile time (`ClassScope#find_ivar_offset`, computed from the per-class `@instance_vars` list), and no
name→offset map is emitted into the class object at runtime (unlike methods, which have the
`method_to_voff` vtable map). So at runtime there is no way to resolve `:@foo` to a slot.

A proper fix emits a per-class ivar-name→offset table (mirroring the vtable) that these methods can
consult — a compiler change, not a lib addition.

---

### 8. Exit-time heap corruption in harness-heavy specs (2026-07-02) — FIXED (distinct from #5)

**FULLY FIXED. Two independent mechanisms, both in the eigenclass path:**
1. eigenclass `@instance_size == 0` (commit d1fe008) — details below.
2. eigenclass metaclass parked in the `%esi` self-register and clobbered by the method-install calls
   (commit 70b3267) — details below.

Both `make selftest` and `make selftest-c` are green (Fails: 0). core/array/clone_spec,
core/kernel/public_send_spec, and the whole core/basicobject/method_missing_spec cluster now run to
completion instead of aborting. (An unrelated, PRE-EXISTING segfault remains in
core/kernel/singleton_class_spec — it crashes identically on the parent commits and is not part of #8.)

**Mechanism 1 FIXED (commit d1fe008): eigenclass `@instance_size == 0`.**
A cluster of specs that lean on the mspec harness's mock/matcher machinery (core/array/clone_spec,
core/kernel/public_send_spec, core/enumerator/*, core/basicobject/method_missing_spec) aborted with
`free(): invalid next size (fast)` in `tgc_sweep` during `exit()` — a stray heap write during the run,
surfaced by the final GC.

Root cause (found with a tgc canary — over-allocate every `__alloc` by 16 bytes, stamp a magic word in
the slack, verify it each sweep): the sole clobbered object was a **size-0 allocation** whose class was
an `Eigenclass_*` with `@instance_size == 0`. Eigenclasses (`class << obj` / `def obj.foo`) are built by
`compile_eigenclass -> __new_class_object`, whose superclass-copy loop starts at slot 6 and therefore
never copies slot 1 (`@instance_size`). Normal classes set `@instance_size` explicitly during
compilation; the eigenclass path did not, leaving it 0. Allocating or cloning an object THROUGH its
singleton class (`self.class == eigenclass`) then computed `__array(0)` — a zero-slot object — and
writing the class pointer (word 0) plus ivars overflowed 9–16 bytes past the calloc'd chunk. It resisted
minimal reproduction because it only fires when a singleton-class-bearing object is later allocated/cloned
deep in the harness. Fix: `compile_eigenclass` now copies the base class's `@instance_size` (slot 1) from
the superclass (slot 3). Recovered clone_spec and public_send_spec (both ran to completion afterwards).

**Mechanism 2 FIXED (commit 70b3267): eigenclass metaclass clobbered in the `%esi` self-register.**
Root-caused via valgrind (memcheck in the docker buildenv) on the clean binary + gdb with ASLR off
(`setarch -R`, which makes the crash 100% deterministic — the nondeterminism was pure ASLR heap-layout
luck).

Minimal 5-line deterministic repro (docs/bugs/eigenclass_self_in_class_body.rb):

    class M
      class << self
        def zqzq1() 1 end
        def zqzq2() 2 end
        def zqzq3() 3 end
      end
    end
    puts M.zqzq1

Valgrind pinpoints an invalid write in `__set_vtable`, called directly from the `class << self` line, with
`vtable` = a 16-byte (4-byte-payload, i.e. bare `Object`) chunk and `off` ≈ 783 (a high method-vtable
slot). So a `class << self` body installs its singleton methods via `__set_vtable(:self, off, fn)`, but
`:self` (the metaclass) is clobbered to a bare Object by the time each install reads it (confirmed
3524-byte metaclass for the first install, 4-byte Object for later ones). `__set_vtable` then writes a
method pointer at slot ~783, far past the 4-byte object, smashing an adjacent malloc header. See the EXACT
ROOT CAUSE below for why.

EXACT ROOT CAUSE (2026-07-02, hardware watchpoint + raw disassembly): the eigenclass binds its metaclass
to a local literally named `:self` (`let(outer_scope, :self)` in compile_eigenclass). The register
allocator FORCES any variable named `:self` into `%esi`, the dedicated self-register (`regalloc.rb`:
`if var == :self; free = @selfreg` where `@selfreg = :esi`). But `%esi` is caller-saved: every method call
clobbers it, and functions reload it from the GLOBAL `self` via `reload_self` at their end (`__set_vtable`
itself ends with `movl self, %esi`). So while the eigenclass installs its methods, each `__set_vtable`
call destroys the metaclass in `%esi`; the compiler then spills the stale/garbage `%esi` back into the
`:self` stack slot (`movl %esi, -24(%ebp)` right after the call) and reloads it for the next install —
which is now a bare-Object/garbage pointer. `__set_vtable` writes a method pointer at slot ~783 into that
4-byte object, smashing an adjacent malloc header. A gdb watchpoint on the slot caught the `push %edi`/
`push %ecx` inside `__set_vtable` writing there; the ≥2-method requirement is because the first install
runs before `%esi` is first clobbered.

THE FIX (commit 70b3267): the metaclass must NOT live in a `:self`-named local (→ %esi) NOR in a plain
stack slot (its offset can still collide with the outgoing-argument area of the same `__set_vtable`
calls, depending on the enclosing frame). It is now stored in a unique per-eigenclass **$-global**
(`$__ec_self__<id>`), immune to both; `EigenclassScope#get_arg(:self)` resolves def-time self to that
global so installs land on the metaclass. This covers BOTH `class << self`/`def self.x` and `def obj.x`
on a local receiver (they share compile_eigenclass).

Two self-hosting gotchas learned here (both would break selftest-c):
- Build the global symbol with `"$__ec_self__#{id}".to_sym`, NOT a `:"...#{id}"` symbol literal — the
  self-hosted compiler does not interpolate `#{}` inside a *symbol literal* (it emits the literal text
  `{unique_id}` into the asm). Plain string interpolation + `.to_sym` is fine.
- `[:assign, [:global, name], value]` is NOT a valid assignment lvalue (get_arg/save reject it, giving
  "Expected an argument on left hand side of assignment"). A `$`-prefixed symbol auto-registers as a
  global and assigns/reads through the normal machinery, so use that as the variable reference.

Note also: the harness Mock's `should_receive` does not actually register an expectation (it sets
@call_counts but not @expectations), so mocked calls print "Mock: No expectation set" — a separate
harness-fidelity gap.

### 9. `singleton_class` on immediates — FIXED (2026-07-02)

`Kernel#singleton_class` (Object#singleton_class) does `(index self 0)` to read the receiver's class
slot; on an immediate (tagged fixnum, nil/true/false, symbol) that dereferences the tagged value as a
pointer and segfaults. core/kernel/singleton_class_spec crashed on `123.singleton_class`. Fixed (commit
ca5fb48) with per-immediate overrides: NilClass/TrueClass/FalseClass return their class;
Integer/Symbol raise `TypeError "can't define singleton"`. Spec now runs (6 passed / 5 failed; the
remainder are feature gaps below, not crashes).

Remaining non-crash gaps in that spec: (a) `class << x; self; end` and `x.singleton_class` create
DISTINCT metaclasses (compile-time compile_eigenclass vs runtime Object#singleton_class both allocate a
fresh one and overwrite slot 0) — Ruby returns the same object; unifying them is the real fix. (b) Float
unimplemented. (c) frozen-state not tracked so a frozen object's singleton isn't frozen.

### 10. core/basicobject/singleton_method_added_spec — segfault (OPEN, resists minimal repro)

Segfaults with a jump to a garbage code address from `Proc#call` (`0x…: ?? ()` <- __method_Proc_call),
i.e. a block/proc with a corrupted `@addr` is invoked. Only the full harness run triggers it: every
extracted construct SURVIVES in isolation — `def obj.x` on BasicObject and Object, defining
`def obj.singleton_method_added(name)`, `Module.new do def self.x; end; def inst; end end`,
`alias_method` inside `class << obj`, and `metaclass.new`. Like the #8 cluster it needs the mspec
harness to reproduce; needs the ASLR-off (`setarch -R`) + gdb/valgrind approach on the real temp binary.
Note the compiler also does NOT implement the `singleton_method_added` HOOK (defining a singleton method
never calls it), so those spec assertions fail regardless — but that is a feature gap, not the crash.

---

## Known Limitations (Cannot Fix)

1. **eval() with dynamic strings** - AOT compilation cannot evaluate runtime strings
2. **Float** - Not implemented (~17 test failures)
3. **Command execution** - Backticks/`%x{}` not implemented (~8 failures)
4. **Rational/Complex** - Not implemented
5. **A block/proc's own block parameter (`proc { |&b| ... }`)** - A proc that declares a block
   parameter and then calls a block passed to *its* invocation (`Proc.new { |&b| b.call }.call { ... }`)
   does not work: `b` resolves to garbage (the `Module` constant). Root cause is the proc calling
   convention: `Proc#call` invokes the body as `@addr(self, @closure, @env, *args)`, where `@closure` is
   the *enclosing* block (for nested `yield`) and there is no slot for a block passed to `.call`. The
   block param `&b` is also normalised to an ordinary positional param before `Function.new`, so `@blockarg`
   (which would map it to `__closure__`) is never set. Supporting this needs a calling-convention change
   (a dedicated call-block slot distinct from `@closure`/`@env`) -- deferred as too invasive. This crashes
   core/proc call_spec, yield_spec and case_compare_spec, which all load `shared/call_arguments`.
6. **Regex: backtracking into groups** (FIXED) - A group is now matched with a continuation (regexp.rb match_from `conts` stack) so a greedy quantifier inside `(...)` can give characters back to a following atom: `/(\d+)(\d)/.match("123")` captures "12","3". Capture indices are position-derived (`__count_cap` + `cap_base`) so backtracking does not shift them. (Remaining: a QUANTIFIED group `(ab)+` still reports one capture per iteration -- separate pre-existing issue.)

---

## Test Framework Issues

Some specs fail due to test framework dependencies:
- `require $spec_filename` - Dynamic require not supported
- `ScratchPad` - Test framework class not available
- `fixture()` - Test helper not implemented

---

## References

- **TODO.md** - Prioritized task list
- **DEBUGGING_GUIDE.md** - Debugging techniques
