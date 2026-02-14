# Core Library Implementations (lib/core/)
Path: /tmp/improve-wrapper/Compiler/lib/core/
Explored: 2026-02-14
Last reviewed: 2026-02-14
Related goals: [COMPLANG](../goals/COMPLANG-compiler-advancement.md), [SELFHOST](../goals/SELFHOST-clean-bootstrap.md), [PURERB](../goals/PURERB-pure-ruby-runtime.md)

## What This Is

The compiler's reimplementation of Ruby's standard library: 49 `.rb` files
totaling 10,634 lines. These are compiled into every program — they provide
the core types (Integer, String, Array, Hash, etc.) and foundational
infrastructure (Object, Class, Kernel) that make Ruby programs work. The
library uses a mix of pure Ruby, low-level s-expressions (the `E[...]`
syntax), and direct assembly operations for performance-critical paths.

## Current State

**Active**, with substantial implementations of core types but significant
gaps in module inclusion, enumerable methods, and I/O. The library is split
into a carefully ordered bootstrap chain documented in
[core.rb](../../lib/core/core.rb) — load order is critical because early
classes (Array, True, False, Nil) must exist before language constructs
that depend on them can work.

### Completeness by File

| File | Lines | Methods | Status |
|------|-------|---------|--------|
| [integer.rb](../../lib/core/integer.rb) | 4,398 | ~189 | **Complete** — full bignum, arithmetic, bitwise, iteration |
| [array.rb](../../lib/core/array.rb) | 1,145 | ~120 | **Substantial** — most methods, but Enumerable not included |
| [string.rb](../../lib/core/string.rb) | 796 | ~69 | **Substantial** — core ops, missing some edge cases |
| [regexp.rb](../../lib/core/regexp.rb) | 805 | ~29 | **Phase 4** — basic matching works, NFA/DFA not started |
| [hash.rb](../../lib/core/hash.rb) | 393 | ~28 | **Partial** — basics work, missing block init, proper delete |
| [class.rb](../../lib/core/class.rb) | 324 | ~30 | **Partial** — vtable machinery, attr_*, module include |
| [exception.rb](../../lib/core/exception.rb) | 236 | ~15 | **Framework** — custom stack, 17 exception classes defined |
| [object.rb](../../lib/core/object.rb) | 236 | ~24 | **Substantial** — identity, comparison, respond_to? |
| [enumerable.rb](../../lib/core/enumerable.rb) | 192 | ~25 | **Skeletal** — ~8 real, rest stubs; not includable |
| [matchdata.rb](../../lib/core/matchdata.rb) | 161 | 14 | **Implemented** — captures, named captures |
| [kernel.rb](../../lib/core/kernel.rb) | 147 | ~14 | **Partial** — puts/print/p, raise, loop |
| [symbol.rb](../../lib/core/symbol.rb) | 135 | 13 | **Implemented** — to_proc, hashing, comparison |
| [file.rb](../../lib/core/file.rb) | 117 | ~5 | **Stub** — mostly not implemented |
| [core.rb](../../lib/core/core.rb) | 111 | 0 | **Meta** — bootstrap load order (48 requires) |
| [class_ext.rb](../../lib/core/class_ext.rb) | 108 | ~6 | **Partial** — extra class methods |
| [float.rb](../../lib/core/float.rb) | 102 | ~6 | **Stub** — float not implemented |
| [enumerator.rb](../../lib/core/enumerator.rb) | 87 | ~4 | **Stub** — minimal |
| [encoding.rb](../../lib/core/encoding.rb) | 86 | ~4 | **Stub** — always returns US-ASCII |
| [base.rb](../../lib/core/base.rb) | 86 | 0 | **Infrastructure** — s-exp helpers |
| [hash_ext.rb](../../lib/core/hash_ext.rb) | 85 | ~3 | **Partial** — hash extensions |
| [range.rb](../../lib/core/range.rb) | 84 | 8 | **Implemented** — iteration, member?, === |
| [array_base.rb](../../lib/core/array_base.rb) | 82 | ~5 | **Bootstrap** — minimal array for splats |
| [integer_base.rb](../../lib/core/integer_base.rb) | 69 | ~4 | **Bootstrap** — fixnum-only Integer |
| [nil.rb](../../lib/core/nil.rb) | 61 | ~13 | **Complete** |
| [stubs.rb](../../lib/core/stubs.rb) | 59 | 0 | **Stubs** — Thread, Module, Fiber empty |
| [rational.rb](../../lib/core/rational.rb) | 58 | 5 | **Partial** |
| [proc.rb](../../lib/core/proc.rb) | 49 | ~4 | **Partial** |
| [true.rb](../../lib/core/true.rb) | 48 | 8 | **Complete** |
| [false.rb](../../lib/core/false.rb) | 48 | 8 | **Complete** |
| [debug.rb](../../lib/core/debug.rb) | 43 | ~1 | **Stub** |
| [io.rb](../../lib/core/io.rb) | 41 | ~3 | **Stub** |
| [numeric.rb](../../lib/core/numeric.rb) | 38 | ~5 | **Partial** |
| [class_ivarinit.rb](../../lib/core/class_ivarinit.rb) | 22 | 0 | **Bootstrap** |
| [complex.rb](../../lib/core/complex.rb) | 19 | ~2 | **Stub** |
| [method.rb](../../lib/core/method.rb) | 19 | ~2 | **Stub** |
| [binding.rb](../../lib/core/binding.rb) | 21 | ~2 | **Stub** |
| [env.rb](../../lib/core/env.rb) | 21 | ~2 | **Stub** |
| [constants.rb](../../lib/core/constants.rb) | 13 | 0 | **Constants** |
| [args.rb](../../lib/core/args.rb) | 12 | 0 | **Argument handling** |
| [dir.rb](../../lib/core/dir.rb) | 10 | ~1 | **Stub** |
| [rbconfig.rb](../../lib/core/rbconfig.rb) | 8 | 0 | **Constants** |
| [math.rb](../../lib/core/math.rb) | 8 | 0 | **Constants** |
| [pp.rb](../../lib/core/pp.rb) | 8 | ~1 | **Stub** |
| [stdio.rb](../../lib/core/stdio.rb) | 8 | ~1 | **Stub** |
| [struct.rb](../../lib/core/struct.rb) | 6 | 0 | **Stub** |
| [fixnum.rb](../../lib/core/fixnum.rb) | 22 | ~3 | **Alias** — delegates to Integer |
| [comparable.rb](../../lib/core/comparable.rb) | 3 | 0 | **Empty** — placeholder |

### Overall: ~550 methods across 49 files. 3 fully complete, 7 substantial, 12 partial, 27+ stubs.

### Bootstrap Chain

The load order in [core.rb](../../lib/core/core.rb) is critical:

1. `base.rb` — s-exp machinery
2. `class.rb`, `kernel.rb`, `object.rb` — foundational OOP
3. `proc.rb` — blocks available
4. `numeric.rb`, `integer_base.rb` — fixnum-only integers
5. `array_base.rb` — splats available
6. `true.rb`, `false.rb`, `nil.rb` — boolean/nil literals
7. `class_ivarinit.rb` — instance variable initialization
8. Then the full types: `range`, `array`, `string`, `hash`, `io`, `file`, `dir`, `comparable`, `integer` (full bignum), `fixnum`, `symbol`, etc.

Before each require, the corresponding class is **completely unavailable**.
E.g., no String objects can exist before `require 'core/string'`.

### Key Architectural Patterns

- **S-expression integration**: Methods like `__true?` use `E[:sexp, ...]` to
  emit assembly-level operations directly, bypassing Ruby semantics.
- **Vtable-based dispatch**: [class.rb](../../lib/core/class.rb) manages virtual
  method tables; method definition writes to vtable slots.
- **Module inclusion broken**: [enumerable.rb](../../lib/core/enumerable.rb)
  exists but cannot be included into Array/Hash — methods are copy-pasted.
- **No dynamic require**: `require` raises LoadError at runtime; all requires
  are processed at compile time.
- **Bignum via limbs**: [integer.rb](../../lib/core/integer.rb) implements
  arbitrary precision using heap-allocated limb arrays for numbers that
  overflow fixnum range.

### FIXME/Bug Density

FIXME markers in lib/core/ files (excluding trivial stubs):

| File | FIXMEs | Notable issues |
|------|--------|---------------|
| [array.rb](../../lib/core/array.rb) | 33 | Module inclusion, efficiency, parse bugs |
| [string.rb](../../lib/core/string.rb) | 17 | Immutability, encoding, efficiency |
| [integer.rb](../../lib/core/integer.rb) | 12 | Bignum limitations, bootstrap issues |
| [object.rb](../../lib/core/object.rb) | 12 | respond_to?, eigenclass, const lookup |
| [hash.rb](../../lib/core/hash.rb) | 7 | Deletion bugs, comparison bugs |
| [class.rb](../../lib/core/class.rb) | 7 | Bootstrap, define_method, attr_writer |
| [stubs.rb](../../lib/core/stubs.rb) | 7 | Everything is a stub |
| [float.rb](../../lib/core/float.rb) | 5 | Float not implemented |
| [symbol.rb](../../lib/core/symbol.rb) | 5 | Type tagging, bootstrap |
| Total (lib/core/) | **~140** | |

## Key Files

- [core.rb](../../lib/core/core.rb) — 111 lines. Bootstrap load order (48 requires).
- [integer.rb](../../lib/core/integer.rb) — 4,398 lines. Full bignum Integer with ~189 methods.
- [array.rb](../../lib/core/array.rb) — 1,145 lines. Array with ~120 methods (Enumerable copy-pasted).
- [string.rb](../../lib/core/string.rb) — 796 lines. String with ~69 methods.
- [regexp.rb](../../lib/core/regexp.rb) — 805 lines. Phase 4 regex engine.
- [hash.rb](../../lib/core/hash.rb) — 393 lines. Hash with probe-based collision resolution.
- [class.rb](../../lib/core/class.rb) — 324 lines. Class/vtable machinery.
- [exception.rb](../../lib/core/exception.rb) — 236 lines. Exception runtime + 17 classes.
- [object.rb](../../lib/core/object.rb) — 236 lines. Object base methods.
- [enumerable.rb](../../lib/core/enumerable.rb) — 192 lines. Skeletal (~8 real methods).
- [stubs.rb](../../lib/core/stubs.rb) — 59 lines. Thread, Module, Fiber stubs.

## AI-AGENT AUTONOMOUS WORK ENABLEMENT (HIGH PRIORITY)

The core library is **the highest-leverage area for autonomous spec improvement**.

### Why This Is Ideal for AI Agents

1. **Self-contained methods**: Each method in lib/core/ is a small, isolated
   unit (typically 5-30 lines). Adding a missing method or fixing a broken
   one doesn't require understanding the whole compiler.

2. **Clear spec expectations**: Each rubyspec file tests specific methods.
   If `core/nil/to_f_spec.rb` fails, the fix is in `lib/core/nil.rb#to_f`.
   The mapping from spec failure to implementation target is usually 1:1.

3. **Low-risk changes**: Adding a method to a core library file cannot break
   the compiler's self-hosting unless it changes existing method behavior.
   New methods are purely additive.

4. **Massive test surface**: There are 525+ rubyspec files covering core
   types that have implementations:
   - core/nil/ (18), core/true/ (8), core/false/ (10) — likely high pass rate
   - core/integer/ (67) — already tracked, mostly passing
   - core/symbol/ (17) — implementation exists, untested
   - core/array/ (128) — extensive implementation, untested against rubyspec
   - core/hash/ (69) — partial implementation
   - core/string/ (139) — substantial implementation
   - core/comparable/ (5) — empty module, needs implementation
   - core/kernel/ (131) — partial, many missing methods

5. **Autonomous workflow**: An agent could: (1) run `./run_rubyspec rubyspec/core/nil/`,
   (2) identify failing methods, (3) implement missing methods in lib/core/nil.rb,
   (4) verify with selftest, (5) re-run specs.

### Quick-Win Targets (Ranked by Expected Pass Rate)

1. **core/nil/** (18 specs) — `nil.rb` is essentially complete. Most specs
   should pass. Any failures would be trivial fixes (missing `to_f`, `to_r`, etc.).

2. **core/true/** (8 specs) — `true.rb` is complete. Expect near-100% pass.

3. **core/false/** (10 specs) — `false.rb` is complete. Expect near-100% pass.
   (Note: some specs may test `singleton_method` which requires more infrastructure.)

4. **core/symbol/** (17 specs) — `symbol.rb` has 13 methods. Good coverage
   but some specs may need methods not yet implemented.

5. **core/integer/** (67 specs) — Already tracked but results truncated at
   5 files. Full run needed to identify gaps.

6. **core/range/** (11 specs) — `range.rb` has 8 methods. Small but well-tested.

## Opportunities

- **Run core/nil, core/true, core/false specs immediately**: These 36 spec
  files test types that are essentially complete. Running them would likely
  show a very high pass rate, demonstrating broader compliance beyond
  language/ alone. Command: `./run_rubyspec rubyspec/core/nil/ rubyspec/core/true/ rubyspec/core/false/`

- **Fill Enumerable methods**: Array, Hash, and Range all need Enumerable
  methods (each_with_object, flat_map, chunk, group_by, reduce, etc.).
  Currently these are either missing or copy-pasted into Array. Implementing
  them in `enumerable.rb` and making `include Enumerable` work would unblock
  dozens of specs across multiple suites.

- **Stub missing methods with `raise`**: Many rubyspec crashes come from
  calling methods that don't exist, causing a segfault instead of an error.
  Adding stub methods that raise `NotImplementedError` would convert crashes
  to failures, producing diagnostic output. Example: `Hash#each_pair`,
  `Hash#select`, `Hash#reject`, `Hash#map` — all tested by rubyspec but
  missing from hash.rb.

- **Fix comparable.rb**: The file is 3 lines (empty module). Implementing
  `<`, `<=`, `>=`, `>`, `between?`, and `clamp` based on `<=>` would make
  Comparable work for Integer, String, and any class that defines `<=>`.
  core/comparable/ has 5 spec files.

- **Complete Hash iteration**: hash.rb has `each` but is missing `each_pair`,
  `each_key`, `each_value`, `select`, `reject`, `map`, `any?`, `all?`,
  `none?`, `find`, `count`, `flat_map`, `to_a` (proper), etc. These are
  straightforward to implement given that `each` works.

- **Fix the 140 FIXMEs**: Many are trivial (e.g., "should handle multiple
  symbols" for private/protected). A systematic triage similar to the
  [BUGAUDIT plan](../plans/BUGAUDIT-validate-bug-workarounds/spec.md)
  but for lib/core/ would identify quick fixes.

## Ideas (not yet plans)

- **Core library FIXME audit**: Categorize the ~140 FIXME markers in lib/core/
  by type (missing feature, known bug, efficiency issue, bootstrap workaround).
  Identify which FIXMEs correspond to rubyspec failures and prioritize those.

- **Method coverage gap analysis**: For each core type with a lib/core/
  implementation, compare implemented methods against the methods tested
  by the corresponding rubyspec/core/ suite. Produce a table of "tested
  but unimplemented" methods ranked by number of specs that test them.

- **Enumerable module fix**: Investigate why `include Enumerable` doesn't
  work (the comment in array.rb says "still need to make including modules
  work"). If module inclusion could be fixed, all Enumerable methods would
  become available to Array, Hash, Range, and any class with `each`.

- **Comparable implementation**: Implement the 6 Comparable methods using
  `<=>`. This is a straightforward, self-contained task that would unblock
  5 spec files and improve Integer/String comparison semantics.

- **Quick-win spec expansion**: Add Makefile targets for:
  ```
  make rubyspec-nil     # ./run_rubyspec rubyspec/core/nil/
  make rubyspec-true    # ./run_rubyspec rubyspec/core/true/
  make rubyspec-false   # ./run_rubyspec rubyspec/core/false/
  make rubyspec-symbol  # ./run_rubyspec rubyspec/core/symbol/
  ```
  These are small suites that would provide quick signal and demonstrate
  broader compliance.

- **Hash method stubs**: Add stubs for the ~20 most commonly tested Hash
  methods that are missing (each_pair, select, reject, map, merge!, update,
  store, fetch, dig, etc.). Even stubs that raise NotImplementedError would
  convert crashes to failures and improve diagnostic output.

- **String method gaps**: String has 69 methods but rubyspec/core/string/
  has 139 spec files. The gap represents ~70 missing methods. A priority
  list based on which are most commonly used in rubyspec/language/ tests
  would identify which String methods to implement first.
