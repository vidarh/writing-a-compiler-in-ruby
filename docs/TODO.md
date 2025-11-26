# Ruby Compiler TODO

**Purpose**: Outstanding tasks prioritized by impact and difficulty. See KNOWN_ISSUES.md for detailed bug descriptions.

## Test Status (2025-11-26 - Current)

**Selftest**: ✅ **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Language Specs**: 78 files
- ✅ **PASSED**: 3 files (4%) - and_spec, not_spec, unless_spec
- ❌ **FAILED**: 25 files (32%) - tests run but fail assertions
- 💥 **CRASHED**: 50 files (64%) - segfaults, hangs, or early exits
- 🎉 **COMPILE FAIL**: 0 files (0%) - **ALL SPECS NOW COMPILE!**

**Individual test results**: 163 passed / 824 failed / 17 skipped (Total: 1004 tests)
- **Pass rate**: 16.2%
- **Expected failures** (known limitations): ~632 tests
  - Regexp not implemented: 507 failures
  - eval() not supported (AOT): ~100 failures
  - Float not implemented: ~17 failures
  - Command execution: ~8 failures
- **Fixable failures**: ~192 tests (19% of failures)

**Recent achievement**: Pattern matching now compiles successfully (2025-11-26)
- Fixed closure variable capture bug in pattern matching
- All language specs now compile (0 COMPILE FAIL)
- Known limitation: pattern-bound variables don't work in nested closures

## Priority 1: CRITICAL - Fix Segmentation Faults (HIGHEST IMPACT)

**Impact**: Blocks 50 spec files (64% of all specs), prevents ~450+ tests from running
**Difficulty**: Medium to High - requires debugging

### Issue: Method Dispatch/Lambda/Proc Causes Crashes

Many specs compile successfully but crash during execution, often after printing warnings like:
```
WARNING:    Method: 'attr'
WARNING:    symbol address = 0x57cdbff0
WARNING:    class 'Class'
```

**Affected specs** (35+ files):
- alias_spec.rb, array_spec.rb, break_spec.rb, case_spec.rb, class_spec.rb
- class_variable_spec.rb, constants_spec.rb, delegation_spec.rb, defined_spec.rb, ensure_spec.rb
- hash_spec.rb, if_spec.rb, keyword_arguments_spec.rb, lambda_spec.rb, line_spec.rb
- loop_spec.rb, magic_comment_spec.rb, metaclass_spec.rb, method_spec.rb, module_spec.rb
- next_spec.rb, numbered_parameters_spec.rb, optional_assignments_spec.rb, or_spec.rb
- pattern_matching_spec.rb, precedence_spec.rb, predefined_globals_spec.rb, private_spec.rb
- proc_spec.rb, return_spec.rb, rescue_spec.rb, safe_navigator_spec.rb, send_spec.rb
- string_spec.rb, super_spec.rb, singleton_class_spec.rb, while_spec.rb, yield_spec.rb

**Common patterns**:
1. Crash after warning about attr/private/create_lambda methods
2. Segfaults during block/lambda/proc execution
3. Possible infinite loops or stack corruption
4. Some specs timeout (hang indefinitely)

**Investigation steps**:
1. Use gdb/valgrind on a simple failing spec (e.g., lambda_spec)
2. Check method lookup/dispatch for attr/private/lambda
3. Review block/lambda/proc memory management
4. Look for stack overflow in recursive calls

**Estimated impact if fixed**: +300 to +450 test passes (30-45% pass rate)

## Priority 2: EASY WINS - Missing Core Methods (HIGH IMPACT, LOW EFFORT)

These can be implemented quickly with significant test impact:

### 2.1 Hash Methods (60+ test impact)

**Files affected**: keyword_arguments_spec, hash_spec, def_spec, END_spec

1. **`Hash#pair`** - Highest priority
   - Used extensively in keyword argument handling
   - Likely returns `[key, value]` for a hash entry
   - Impact: ~30 tests

2. **`Hash#hash_splat`** - High priority
   - Used for `**kwargs` expansion
   - Impact: ~20 tests

3. **`Hash#merge`** - Medium priority
   - Needed for `**` operator in hash literals
   - Impact: ~10 tests

**Estimated effort**: 2-4 hours total
**Estimated impact**: +60 tests passing

### 2.2 Catch/Throw (18+ test impact)

**File affected**: throw_spec (all 18 tests fail)

- **`Kernel#catch(symbol, &block)`** - Execute block, catch throw
- **`Kernel#throw(symbol, value=nil)`** - Exit to matching catch

**Estimated effort**: 1-2 hours
**Estimated impact**: +18 tests passing

### 2.3 String/Regexp Matching (10+ test impact)

**File affected**: match_spec (10 failures)

- **`String#=~(pattern)`** - Return match position or nil
- **`Regexp#=~(string)`** - Return match position or nil

Note: Since Regexp is not implemented, these can stub to:
- Return nil (no match)
- Or raise NotImplementedError with clear message

**Estimated effort**: 30 minutes (stub implementation)
**Estimated impact**: +10 tests passing (or better error messages)

### 2.4 Loop Control (6+ test impact)

**Files affected**: until_spec, loop_spec

- **`Object#redo`** - Restart current iteration of loop without re-evaluating condition

**Estimated effort**: 1 hour
**Estimated impact**: +6 tests passing

### 2.5 Fix break Return Value (3 test impact)

**File affected**: until_spec

**Issue**: `break` with no arguments returns `false` instead of `nil`

**Fix**: Change default break value from false to nil in compiler

**Estimated effort**: 15 minutes
**Estimated impact**: +3 tests passing

**Total Priority 2 impact**: +97 tests (10% pass rate increase) in ~8 hours work

## Priority 3: String Interpolation Bug (40+ test impact)

**Files affected**: string_spec (21 failures), heredoc_spec (10 failures)

**Issue**: Simple interpolation without braces is broken:
- `"#$var"` → outputs literal `"#$var"` instead of variable value
- `"#@var"` → outputs literal `"#@var"` instead of instance variable
- `"#@@var"` → outputs literal `"#@@var"` instead of class variable

**Works correctly**: `"#{expr}"` (braced interpolation)

**Examples**:
```ruby
$x = "hello"
"#$x"     # Expected: "hello", Got: "#$x"
"#{$x}"   # Works: "hello"
```

**Root cause**: Parser doesn't recognize `#$var` / `#@var` / `#@@var` as interpolation

**Estimated effort**: 2-3 hours (parser fix in string.rb or scanner.rb)
**Estimated impact**: +40 tests passing

## Priority 4: Loop Control Issues (8+ test impact)

**File affected**: until_spec (8 failures)

**Issues**:
1. `next` in modifier form doesn't work correctly
   ```ruby
   x = 0
   until x > 3
     x += 1
     next if x == 2  # Doesn't skip properly
     sum += x
   end
   # Expected: sum = 7 (1+3+4), Got: different result
   ```

2. `begin...end until condition` doesn't execute body at least once
   ```ruby
   x = 0
   begin
     x += 1
   end until x > 5
   # Should execute body once before checking condition
   ```

**Estimated effort**: 2-3 hours
**Estimated impact**: +8 tests passing

## Priority 5: Hash Edge Cases (15+ test impact)

**File affected**: hash_spec

**Issues**:
1. Empty hash keys: `{=> value}` should create `{nil => value}`, creates `{}`
2. `**nil` in hash literal should expand to `{}` or raise TypeError
3. Missing `Hash#to_hash` for splatting

**Estimated effort**: 2-3 hours
**Estimated impact**: +15 tests passing

## Priority 6: BEGIN/END Blocks (14+ test impact)

**Files affected**: BEGIN_spec (crashes), END_spec (14 failures)

**Issue**: BEGIN and END blocks not implemented

**Estimated effort**: 4-6 hours (moderate complexity)
**Estimated impact**: +14 tests passing (BEGIN_spec may also work)

## Priority 7: Missing Utility Methods (20+ test impact)

**Files affected**: Various

Low-hanging fruit, can be stubbed:

1. **`Kernel#fixture`** - Used by test framework (toplevel_binding_spec, END_spec)
   - Can stub to return file path for test fixtures
   - Impact: ~10 tests

2. **`Object#singleton_class`** - Return object's singleton class
   - Impact: ~2 tests (execution_spec)

3. **`Object#instance_eval`** - Evaluate block in object's context
   - Impact: Variable (keyword_arguments_spec)

4. **`Object#proc`** - Create Proc from block
   - Impact: ~5 tests (order_spec)

5. **`Object#do`** - Unknown method (order_spec issue?)
   - Impact: ~10 tests (may be parser bug, not real method)

**Estimated effort**: 3-4 hours total (mostly stubs)
**Estimated impact**: +20 tests passing

## Summary: Realistic Improvement Plan

### Phase 1: Quick Wins (1-2 days, ~8-10 hours)
- Priority 2: Missing methods (+97 tests)
- Fix break return value (+3 tests)
- **Total**: +100 tests → **26% pass rate**

### Phase 2: Parser Fixes (2-3 days)
- Priority 3: String interpolation (+40 tests)
- Priority 4: Loop control (+8 tests)
- **Total**: +148 tests → **31% pass rate**

### Phase 3: Hash & Utilities (2-3 days)
- Priority 5: Hash edge cases (+15 tests)
- Priority 7: Utility methods (+20 tests)
- **Total**: +183 tests → **34% pass rate**

### Phase 4: BEGIN/END (1-2 days)
- Priority 6: BEGIN/END blocks (+14 tests)
- **Total**: +197 tests → **36% pass rate**

### Phase 5: Critical Investigation (1-2 weeks)
- Priority 1: Fix segfaults (+300-450 tests)
- **Total**: +500-650 tests → **50-65% pass rate**

**Realistic near-term goal** (without segfault fixes): **35-40% pass rate** (350-400 tests)
**Optimistic long-term goal** (with segfault fixes): **50-65% pass rate** (500-650 tests)

## Known Limitations (Cannot Fix)

These are fundamental architectural limitations documented in KNOWN_ISSUES.md:

1. **Regexp not implemented** - 507 test failures (65% of all failures)
2. **eval() not supported** - ~100 test failures (AOT compiler limitation)
3. **Float not implemented** - 17 test failures
4. **Backticks/command execution** - 8 test failures

**Total unfixable**: ~632 tests (63% of failures)

These limitations mean maximum achievable pass rate is approximately **80-85%** (800-850 tests) even with all bugs fixed.

## Not Prioritized (Low Impact)

- Character escape sequences - 2 test failures
- Timeout/infinite loops (def_spec, assignments_spec) - 2+ files but needs investigation
- Pattern matching nested closures - Known limitation, documented
