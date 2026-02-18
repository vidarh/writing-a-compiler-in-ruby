ENUMOD
Created: 2026-02-18

# Enable the Enumerable Module and Fix Broken Methods

[COMPLANG] Uncomment the Enumerable module require, fix 3 broken methods (`all?`, `reject`, `inject`), and add `include Enumerable` to Array, Hash, and Range — giving these classes dozens of inherited methods for free and unblocking rubyspec tests that depend on Enumerable behavior.

## Goal Reference

[COMPLANG](../../goals/COMPLANG-compiler-advancement.md)

Also advances [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md): removing the 10-year-old commented-out require and the FIXME markers noting "belongs in Enumerable" addresses technical debt in the bootstrap chain.

## Prior Plans

- **[COMPARABLE](../archived/COMPARABLE-implement-comparable-module/spec.md)** (Status: IMPLEMENTED): Implemented the Comparable module using the same `__include_module` vtable mechanism that this plan relies on. COMPARABLE confirmed that: (1) `include` works at compile time and runtime, (2) `__include_module` only copies uninitialized vtable slots (so class-defined methods take priority over module methods), (3) class reopening at the bottom of a module file works for adding `include` after the target class is defined. This plan uses the same proven pattern.

## Root Cause

The `require 'core/enumerable'` line has been **commented out** in [lib/core/core.rb:73](../../lib/core/core.rb) since September 2015 (commit 8830f41), with the comment: *"commented out the Enumerable module require until I figure out where it's safe to load it (bootstrapping issues)."*

The bootstrap concern was valid in 2015 but is no longer relevant. The current load order in [core.rb](../../lib/core/core.rb) places the commented-out `enumerable` require at line 73, which is:
- **After** `proc.rb` (line 63) — so blocks work
- **After** `array_base.rb` (line 66) — so Array exists in minimal form
- **After** `nil.rb` (line 69) — so nil/true/false work
- **Before** `array.rb` (line 75) — so Array can `include Enumerable` when it loads

This ordering is exactly correct: Enumerable should be defined before Array so that Array's class definition can include it.

Additionally, 3 of Enumerable's methods are broken due to stale workarounds:

1. **`all?`** ([enumerable.rb:3-10](../../lib/core/enumerable.rb)): The `unless yield(item); return false; end` body is commented out. The method always returns `true` regardless of block return values. The `unless` keyword works fine in blocks in the current compiler (used in [comparable.rb:34-35](../../lib/core/comparable.rb), [regexp.rb:437+](../../lib/core/regexp.rb)).

2. **`reject`** ([enumerable.rb:152-160](../../lib/core/enumerable.rb)): Same issue — the `unless yield(item); items << item; end` body is commented out. The method always returns an empty array.

3. **`inject`** ([enumerable.rb:121-131](../../lib/core/enumerable.rb)): The fallback for when `initial` is nil (use first element as accumulator) is commented out. The method works with an explicit initial value but fails silently with no initial value, which is the common Ruby idiom `[1,2,3].inject(:+)`.

Finally, Array has at least 7 FIXME markers noting methods that "belong in Enumerable" or are "cut and paste from Enumerable" ([array.rb:42](../../lib/core/array.rb), [array.rb:51](../../lib/core/array.rb), [array.rb:83](../../lib/core/array.rb), [array.rb:99](../../lib/core/array.rb), [array.rb:112](../../lib/core/array.rb), [array.rb:1113](../../lib/core/array.rb)), and line 5 has a commented-out `include Enumerable`.

## Infrastructure Cost

Zero. This uncomments one line in [core.rb](../../lib/core/core.rb), fixes 3 methods in [enumerable.rb](../../lib/core/enumerable.rb), and adds `include Enumerable` statements to 3 existing class files. No new files, no build system changes, no tooling changes. The module inclusion infrastructure (`__include_module` in [class.rb:94-111](../../lib/core/class.rb)) is already proven by COMPARABLE.

## Scope

**In scope:**

1. Uncomment `require 'core/enumerable'` at [lib/core/core.rb:73](../../lib/core/core.rb)
2. Fix `all?` in [enumerable.rb:3-10](../../lib/core/enumerable.rb): uncomment the `unless yield(item); return false; end` body. If `unless` in blocks causes a compiler issue, rewrite as `if !yield(item); return false; end` (equivalent).
3. Fix `reject` in [enumerable.rb:152-160](../../lib/core/enumerable.rb): uncomment the `unless yield(item); items << item; end` body. Same `unless`→`if !` fallback if needed.
4. Fix `inject` in [enumerable.rb:121-131](../../lib/core/enumerable.rb): uncomment the initial-value fallback so `inject` without an explicit initial value uses the first element as the accumulator.
5. Add `include Enumerable` to Array in [lib/core/array.rb](../../lib/core/array.rb) (uncomment line 5)
6. Add `include Enumerable` to Hash in [lib/core/hash.rb](../../lib/core/hash.rb) (Hash defines `each`, so it qualifies)
7. Add `include Enumerable` to Range in [lib/core/range.rb](../../lib/core/range.rb) (Range defines `each`, so it qualifies)
8. Validate with `make selftest`, `make selftest-c`, and `make spec`

**Out of scope:**
- Removing Array's duplicate methods (e.g., `select`, `collect`, `detect`, `any?`, `all?`, `reject`). These are copy-pasted from Enumerable but may have Array-specific optimizations. Because `__include_module` only fills uninitialized vtable slots, Array's versions will take priority — so keeping them is harmless and removing them is a separate cleanup task.
- Implementing stub methods in Enumerable (`max`, `min`, `sort`, `sort_by`, `partition`, `to_a`, `to_set`, `zip`) — these remain as stubs. Classes that need them (Array) already have their own implementations.
- Adding `each_with_object`, `flat_map`, `chunk`, `group_by`, `reduce`, `count`, `none?`, `first`, `take`, `drop`, or other Enumerable methods not currently in the module — those are future additions.
- Running rubyspec suites (that would be a follow-up to measure impact)

## Expected Payoff

**Immediate:**
- Hash gains `any?`, `all?`, `collect`/`map`, `select`/`find_all`, `reject`, `detect`/`find`, `include?`/`member?`, `inject`, `each_with_index`, `each_cons`, and `entries` — approximately 12 methods that Hash currently lacks entirely
- Range gains the same ~12 methods (Range currently has 8 methods total, nearly doubling its method count)
- Array gains any Enumerable methods it doesn't already define locally (most are duplicated, but `each_cons`, `entries`, `member?` alias are likely missing)
- Enumerable's `all?`, `reject`, and `inject` actually work correctly instead of being silently broken

**Downstream (COMPLANG):**
- `rubyspec/core/hash/` tests calling `Hash#select`, `Hash#map`, `Hash#any?`, `Hash#all?`, `Hash#detect`, etc. will no longer crash with "undefined method" — they'll either pass or produce meaningful failures
- `rubyspec/core/array/` tests using Enumerable methods indirectly (via `include?`, `inject`, etc.) become more robust
- `rubyspec/core/range/` tests using iteration methods can run
- The exploration notes ([core-library-implementations.md](../../exploration/core-library-implementations.md)) identify Hash missing `each_pair`, `select`, `reject`, `map`, `any?`, `all?`, `none?`, `find`, `count`, `flat_map`, `to_a` as a significant gap — this plan directly addresses 10 of those 11

**Technical debt:**
- The 10-year-old commented-out require is resolved
- Array's 7 "belongs in Enumerable" FIXME markers become documentation of intentional overrides rather than TODOs
- The Enumerable module becomes a living, tested part of the runtime rather than dead code

## Proposed Approach

1. **Uncomment the require**: Change `#require 'core/enumerable'` to `require 'core/enumerable'` in [lib/core/core.rb:73](../../lib/core/core.rb).

2. **Fix `all?`**: Uncomment the body. Try `unless` first; if it causes a compiler issue in block context, rewrite as:
   ```ruby
   def all?
     self.each do |item|
       if !yield(item)
         return false
       end
     end
     return true
   end
   ```

3. **Fix `reject`**: Same approach — uncomment or rewrite with `if !`.

4. **Fix `inject`**: Uncomment the initial-value fallback. If `self[1..-1]` or `self.first` causes issues, use an index-based approach:
   ```ruby
   def inject(initial = nil, &block)
     acc = initial
     first = true
     self.each do |item|
       if acc.nil? && first
         acc = item
         first = false
       else
         first = false
         acc = yield(acc, item)
       end
     end
     return acc
   end
   ```

5. **Add `include Enumerable`**: Uncomment in Array, add to Hash and Range. For Hash and Range, follow the COMPARABLE pattern — either add directly in the class file or reopen at the bottom of enumerable.rb if load ordering requires it:
   - Array: load order is core.rb:75 (after enumerable at 73) — add directly in array.rb
   - Hash: load order is core.rb:77 (after enumerable at 73) — add directly in hash.rb
   - Range: load order is core.rb:74 (after enumerable at 73) — add directly in range.rb

6. **Validate**: Run `make selftest` and `make selftest-c` to confirm no regressions. Run `make spec` to check for spec regressions.

## Acceptance Criteria

- [ ] [lib/core/core.rb](../../lib/core/core.rb) has `require 'core/enumerable'` uncommented (not `#require`)
- [ ] [lib/core/enumerable.rb](../../lib/core/enumerable.rb) `all?` method has a working body that returns `false` when the block returns a falsy value (not always `true`)
- [ ] [lib/core/enumerable.rb](../../lib/core/enumerable.rb) `reject` method has a working body that collects items for which the block returns falsy (not always empty array)
- [ ] [lib/core/enumerable.rb](../../lib/core/enumerable.rb) `inject` method works without an explicit initial value (uses first element as accumulator)
- [ ] [lib/core/array.rb](../../lib/core/array.rb) contains `include Enumerable`
- [ ] [lib/core/hash.rb](../../lib/core/hash.rb) contains `include Enumerable`
- [ ] [lib/core/range.rb](../../lib/core/range.rb) contains `include Enumerable`
- [ ] `make selftest` passes
- [ ] `make selftest-c` passes
- [ ] `make spec` passes (no regressions)
- [ ] A Hash object responds to `select` (verified by a test program compiled with the compiler): `{a: 1, b: 2}.select { |k, v| v > 1 }` does not crash with "undefined method"

## Open Questions

- Does `unless yield(item)` work correctly inside a block passed to `each`? The `unless` keyword works in [comparable.rb](../../lib/core/comparable.rb) but those uses are not inside `yield`-receiving blocks. If `unless` combined with `yield` triggers a compiler bug, the `if !yield(item)` rewrite is the fallback.
- Does Hash's `each` yield key-value pairs in a way compatible with Enumerable methods? Hash#each typically yields `|key, value|` pairs, but some Enumerable methods (like `include?`) pass a single argument to the comparison. This may require Hash-specific overrides for some methods, but that's a follow-up concern — the base inclusion still provides value.
- The `inject` fix uses a `first` flag pattern. An alternative is to detect `initial.nil?` and shift the first element, but this requires `self.first` to exist on all Enumerable includers (it doesn't on Hash). The flag approach is more portable.

---
*Status: PROPOSAL - Awaiting approval*
