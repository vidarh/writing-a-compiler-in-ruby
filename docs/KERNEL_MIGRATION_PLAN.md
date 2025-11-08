# Kernel Method Migration & Module Include Fixes

**Status**: In Progress
**Goal**: Move methods from Object to Kernel now that include works, and fix module include ordering issues

## CRITICAL: Bootstrap Ordering Considerations

**Why duplicate methods may be necessary:**

Some methods exist in both Object and Kernel because of bootstrap ordering constraints. Early in the bootstrap sequence (lib/core/core.rb), certain classes are loaded before others, and methods may need simpler implementations to avoid dependencies on classes that don't exist yet.

**Before removing any "duplicate" method, consider:**

1. **Bootstrap order matters**: If a method in Object is loaded before Kernel, or uses features not yet available when Kernel is loaded, it may need to stay in both places
2. **Simpler early versions**: Early bootstrap may require stub/simple versions that are later replaced with full implementations
3. **Crash investigation**: If moving a method causes crashes, check:
   - What order are Object vs Kernel loaded? (Check lib/core/core.rb lines 60-62)
   - Does the method depend on classes loaded after Kernel but before Object?
   - Does the method use features (Array, Hash, String, etc.) that may not exist when Kernel initializes?

**Examples of valid duplicates:**
- Kernel has simple `puts` (uses s-expression), Object has complex `puts` (uses Array, String#to_s, String#ord)
- If simple version is needed during early bootstrap before Array/String are available

**Resolution strategy:**
1. Try moving the method
2. Run selftest/selftest-c
3. **If crashes occur**: Revert and document why both versions are needed
4. **If tests pass**: Keep the migration, remove duplicate

**Document findings in this file** when investigating crashes to avoid repeated work.

## Completed

- [x] **loop** (Phase 1.0) - Removed from Object, now inherited from Kernel
  - Validated: selftest ✓, selftest-c ✓, manual test ✓
- [x] **exit** (Phase 1.1) - COMPLETED (2025-11-08) - Removed from Object, now inherited from Kernel
  - Validated: selftest ✓, selftest-c ✓
- [x] **Array()** (Phase 1.2) - COMPLETED (2025-11-08) - Removed from Object, now inherited from Kernel
  - Validated: selftest ✓, selftest-c ✓
- [x] **raise** (Phase 2.2) - COMPLETED (2025-11-08) - Moved Object's sophisticated version to Kernel
  - Object's version handles both String and Exception objects
  - Kernel's simple version replaced with Object's implementation
  - Validated: selftest ✓, selftest-c ✓

## Phase 1: Simple Method Migrations (No Dependencies)

These methods can be moved immediately as they have no complex dependencies:

### 1. exit (lib/core/object.rb:147-149)
**Current location**: Object
**Target location**: Kernel (already has simple `raise`)
**Complexity**: LOW
**Implementation**:
```ruby
# In lib/core/kernel.rb - ADD:
def exit(code)
  %s(exit (callm code __get_raw))
end

# In lib/core/object.rb - REMOVE lines 146-149
```
**Validation**:
- selftest ✓
- selftest-c ✓
- No specific spec (exit would terminate test runner)

---

### 2. Array (lib/core/object.rb:205-213)
**Current location**: Object
**Target location**: Kernel
**Complexity**: LOW
**Implementation**:
```ruby
# In lib/core/kernel.rb - ADD:
def Array(arg)
  if arg.respond_to?(:to_ary)
    arg.to_ary
  elsif arg.respond_to?(:to_a)
    arg.to_a
  else
    [arg]
  end
end

# In lib/core/object.rb - REMOVE lines 204-213
```
**Validation**:
- selftest ✓
- selftest-c ✓
- Check if any specs use Array()

---

## Phase 2: Complex Method Migrations (Conflicts to Resolve)

These methods have conflicts or complexity:

### 3. puts - KEEP BOTH (Bootstrap Requirement)

**DECISION: Both implementations must stay - this is correct bootstrap design**

**Kernel's puts** (lib/core/kernel.rb:3-5):
```ruby
def puts s
  %s(puts (index s 1))  # Simple s-expression, single argument
end
```
- **Dependencies**: None (uses only s-expressions)
- **Purpose**: Early bootstrap (loaded at core.rb:61 before Array/String exist)
- **Limitations**: Single argument only, no splat, no to_s conversion

**Object's puts** (lib/core/object.rb:148-176):
```ruby
def puts *str
  # Complex: handles splat, multiple args, to_s, newline handling
end
```
- **Dependencies**: Array (splat), String (to_s, [], ord), Integer
- **Purpose**: Full functionality after String is loaded (core.rb:76)
- **Overrides**: Kernel's simple version via normal method override

**Bootstrap Timeline**:
1. Line 61: Kernel loaded - simple puts available
2. Line 62: Object loaded, includes Kernel, OVERRIDES with complex puts
3. Line 66-76: Array/String loaded - complex puts can now be called safely
4. All classes inherit Object's complex puts

**Why both are needed**:
- Kernel's simple version: For any puts calls between lines 61-76 (before String exists)
- Object's complex version: Normal use after bootstrap completes
- This is a VALID use case for duplicate methods (see Bootstrap Ordering Considerations above)

**Status**: NO MIGRATION NEEDED - current design is correct

---

### 4. raise - MIGRATE Object's version to Kernel

**DECISION: Move Object's sophisticated version to Kernel, remove Kernel's simple version**

**Analysis**:
- **Bootstrap check**: Both versions defined at lines 61-62, BEFORE exception.rb (line 89)
  - No bootstrap advantage to having simple version
  - RuntimeError doesn't exist when either is defined
  - Both only execute when called (after exception.rb loads)
- **Usage check**: Only Object#method_missing calls raise (line 85)
  - No early bootstrap code uses raise
- **Functionality**: Object's version is strictly more powerful
  - Handles both String messages AND Exception objects
  - Kernel's version only handles strings

**Implementation**:
```ruby
# In lib/core/kernel.rb - REPLACE lines 8-13:
def raise(msg_or_exc)
  # Handle both String messages and Exception objects
  if msg_or_exc.is_a?(StandardError)
    exc = msg_or_exc
  else
    exc = RuntimeError.new(msg_or_exc)
  end
  $__exception_runtime.raise(exc)
  # Never returns
end

# In lib/core/object.rb - REMOVE lines 20-30
# (Mark as "MOVED TO KERNEL")
```

**Validation**:
- selftest ✓ (uses raise)
- selftest-c ✓
- Check exception specs (if any work)

**Status**: COMPLETED (2025-11-08) - Migrated successfully, all tests pass

---

## Phase 3: Module Include Ordering Fixes

Fix ordering issues where classes include modules defined later:

### 5. Comparable Module Ordering - COMPLETED (2025-11-08)

**Problem**: Integer includes Comparable (integer.rb:13), but Comparable was defined AFTER Integer

**Solution**: Moved `require 'core/comparable'` to before `require 'core/integer'` in lib/core/core.rb

**New order** (lib/core/core.rb):
```
Line 80: require 'core/dir'
Line 81: require 'core/comparable'   # Define Comparable first
Line 82: require 'core/integer'      # Then Integer can include it
```

**Validation Results**:
- selftest ✓ (1 expected failure)
- selftest-c ✓ (1 expected failure)
- Integer comparison specs:
  - lt_spec.rb: 4/5 passed (1 failure in coerce exception handling)
  - gt_spec.rb: 2/5 passed
  - lte_spec.rb: 5/7 passed
  - gte_spec.rb: 2/5 passed

**Impact**: Integer comparison operators now work via Comparable include. Some spec failures remain due to other issues (Float comparisons, exception handling).

---

### 6. Enumerable Module (Future)
**Problem**: Array has `# include Enumerable` commented out (array.rb:5)
**Status**: Enumerable not fully implemented yet
**Current order** (lib/core/core.rb):
```
Line 75: require 'core/array'
Line 92: require 'core/enumerator'
# Enumerable not in core.rb at all!
```
**Complexity**: HIGH - Enumerable is not implemented

**Investigation needed**:
- Where is Enumerable defined? (search codebase)
- What methods does it provide?
- What dependencies does it have?
- Can we enable Array include Enumerable after reordering?

**Deferred**: Until Enumerable is implemented

---

## Testing Strategy

For each migration:

1. **Pre-migration baseline**:
   ```bash
   make selftest 2>&1 | tee baseline_selftest.txt
   make selftest-c 2>&1 | tee baseline_selftest-c.txt
   ```

2. **Make change** (move ONE method)

3. **Post-migration validation**:
   ```bash
   make selftest    # Must match baseline
   make selftest-c  # Must match baseline
   ```

4. **Spec validation** (if relevant specs exist):
   ```bash
   ./run_rubyspec rubyspec/core/kernel/[method]_spec.rb
   ```

5. **If any test fails**: REVERT immediately and investigate

---

## Priority Order

**Immediate (Low Risk)**:
1. exit - trivial, no conflicts
2. Array - simple, might fix specs

**Medium (Conflicts to resolve)**:
3. puts - resolve which implementation to keep
4. raise - resolve which implementation to keep

**Later (Requires investigation)**:
5. Comparable ordering - test carefully with integer specs
6. Enumerable - deferred until implemented

---

## Notes

- **CRITICAL**: Only move ONE method at a time
- Always run full regression suite (selftest + selftest-c) after each change
- Document which implementation was chosen for conflicting methods
- Keep FIXME comments as breadcrumbs during migration
- Update this doc as items are completed
