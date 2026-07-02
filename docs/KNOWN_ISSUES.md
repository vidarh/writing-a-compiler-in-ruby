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

### 5. Heap corruption gating the core/kernel cluster (2026-07-01)

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
