# Ruby Compiler TODO

**Purpose**: Outstanding tasks prioritized by impact and difficulty. See KNOWN_ISSUES.md for detailed bug descriptions and RUBYSPEC_CRASH_ANALYSIS.md for crash categorization.

## Test Status (2025-11-26 - Post Phase 0)

**Selftest**: ✅ **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Language Specs**: 78 files
- ✅ **PASSED**: 3 files (4%) - and_spec, not_spec, unless_spec
- ❌ **FAILED**: 24 files (31%) - tests run but fail assertions
- 💥 **CRASHED**: 51 files (65%) - segfaults, timeouts, or early exits
- 🎉 **COMPILE FAIL**: 0 files (0%) - **ALL SPECS NOW COMPILE!**

**Individual test results**: 166 passed / 801 failed / 16 skipped (Total: 983 tests)
- **Pass rate**: 16.9% (up from 16.2%)
- **Expected failures** (known limitations): ~632 tests
  - Regexp not implemented: 507 failures
  - eval() not supported (AOT): ~100 failures
  - Float not implemented: ~17 failures
  - Command execution: ~8 failures
- **Fixable failures**: ~169 tests (17% of failures)

**Phase 0 Results** (2025-11-26):
- Stubbed 15+ methods: attr, prepend, extend, class_eval, module_function, catch, throw, redo, fixture, singleton_class, String#=~, Regexp#=~, Hash#pair, Hash#hash_splat
- Added 30s timeout to run_rubyspec to prevent infinite hangs
- +3 tests passing (163→166)
- delegation_spec: CRASH→FAIL (unblocked 23 tests)
- Fixed critical selftest-c regression (NotImplementedError→RuntimeError)

**Crash Analysis Complete**: See docs/RUBYSPEC_CRASH_ANALYSIS.md
- Category A (Missing Methods): 18 specs - EASY
- Category B (Lambda/Block Segfaults): 16 specs - HARD
- Category C (Startup Segfaults): 5 specs - VERY HARD
- Category D (Exception Framework): 11 specs - MEDIUM (single-point fix)

---

## Phase 0: SUPER-QUICK STUBS (2-4 hours, 30+ specs unblocked)

**Strategy**: Implement minimal method stubs first to unblock tests, then add full implementations later.
**Impact**: Convert 18 "missing method" crashes to running tests (Category A)
**Effort**: ~5-15 minutes per method

### 0.1 Fix Exception Framework (30 minutes, 11 specs)

**Issue**: "Unhandled exception: wrong number of arguments (given 0, expected 1)"
**Root cause**: Exception constructor expects wrong number of arguments

**Files affected** (Category D from crash analysis):
- BEGIN_spec, ensure_spec, if_spec, next_spec, pattern_matching_spec
- line_spec, magic_comment_spec, method_spec, numbered_parameters_spec
- or_spec, predefined_globals_spec

**Fix**: Check Exception.new and StandardError.new - likely needs to accept 0 or 1 argument
**Location**: lib/core/exception.rb or similar
**Priority**: HIGHEST - Single fix unblocks 11 specs (22% of crashes)

### 0.2 Stub Missing Visibility Methods (30 minutes, 6 specs)

**Methods to stub**:
1. **`Module#private`** - Mark methods as private
   - Stub: Accept method names, do nothing (visibility not enforced anyway)
   - Files affected: break_spec, defined_spec, private_spec
   - Priority: HIGH

2. **`Module#attr`** - Create attribute accessor
   - Stub: `define_method(name) { instance_variable_get("@#{name}") }`
   - Files affected: alias_spec
   - Priority: MEDIUM

3. **`Module#prepend`** - Prepend module to class
   - Stub: Similar to `include` but prepends instead of appends
   - Files affected: constants_spec, optional_assignments_spec
   - Priority: MEDIUM

4. **`Module#extend`** - Extend object with module methods
   - Stub: Add module methods as singleton methods
   - Files affected: class_variable_spec
   - Priority: MEDIUM

**Implementation**: Add to lib/core/module.rb or lib/core/class.rb
**Estimated time**: 5-10 minutes each = 30 minutes total
**Impact**: +6 specs unblocked

### 0.3 Stub Metaprogramming Methods (45 minutes, 7 specs)

**Methods to stub**:
1. **`Module#class_eval`** - Evaluate code in class context
   - Stub: `yield` the block (basic version)
   - Files affected: delegation_spec
   - Priority: HIGH

2. **`Class#create_lambda`** (likely custom test method)
   - Stub: `lambda { |*args| yield(*args) }`
   - Files affected: lambda_spec
   - Priority: HIGH

3. **`Module#module_function`** - Make methods both instance and module methods
   - Stub: Do nothing (or copy methods)
   - Files affected: send_spec
   - Priority: MEDIUM

4. **Test helper methods**: `msg`, `x`, `v`, `meth`, `object`
   - These appear to be spec-specific helpers defined in test files
   - May need to check why they're not being found
   - Files affected: rescue_spec, return_spec, yield_spec, undef_spec, assignments_spec
   - Priority: LOW (investigate first)

**Implementation**: Add to lib/core/module.rb, lib/core/class.rb, or lib/core/kernel.rb
**Estimated time**: 5-10 minutes each = 45 minutes total
**Impact**: +7 specs unblocked (potentially more with helper methods)

### 0.4 Stub Missing Core Methods (1 hour, ~50 tests)

**Hash methods** (highest priority):
1. **`Hash#pair`** - Return [key, value] pair
   - Stub: `def pair; [keys.first, values.first]; end`
   - Full impl later: Proper iteration support
   - Files affected: keyword_arguments_spec, hash_spec, def_spec, END_spec
   - Impact: ~30 tests

2. **`Hash#hash_splat`** - Handle **kwargs
   - Stub: `def hash_splat; self; end`
   - Full impl later: Proper expansion logic
   - Impact: ~20 tests

3. **`Hash#merge`** - Merge hashes
   - Stub: `def merge(other); dup.update(other); end` (if update exists)
   - Or: Copy keys manually
   - Impact: ~10 tests

**Control flow methods**:
4. **`Kernel#catch`** - Catch thrown values
   - Stub: `def catch(tag); yield; end` (no actual catching)
   - Full impl later: Proper catch/throw mechanism
   - Files affected: throw_spec
   - Impact: ~18 tests

5. **`Kernel#throw`** - Throw to catch
   - Stub: `def throw(tag, value=nil); end` (no-op)
   - Full impl later: Actual non-local return
   - Impact: ~18 tests

**String methods**:
6. **`String#=~`** - Match against pattern
   - Stub: `def =~(pattern); nil; end`
   - Full impl: When regexp is implemented
   - Files affected: match_spec
   - Impact: ~10 tests

7. **`Regexp#=~`** - Match string
   - Stub: `def =~(string); nil; end`
   - Impact: ~10 tests

**Loop control**:
8. **`Kernel#redo`** - Restart loop iteration
   - Stub: Raise NotImplementedError with clear message
   - Full impl later: Proper loop restart
   - Files affected: until_spec, loop_spec
   - Impact: ~6 tests

**Utility methods**:
9. **`Object#singleton_class`** - Get singleton class
   - Stub: Return class (not correct but won't crash)
   - Full impl later: Proper singleton class support
   - Impact: ~2 tests

10. **`Kernel#fixture`** - Test framework helper
    - Stub: `def fixture(name); "fixtures/#{name}"; end`
    - Impact: ~10 tests

**Estimated time**: 5-10 minutes each = 1 hour total
**Impact**: +50-60 tests passing

### Phase 0 Total Impact
- **Time**: 2-4 hours
- **Specs unblocked**: 30+ specs (from Category A + D)
- **Tests fixed**: 100+ tests
- **New pass rate**: ~26-30% (260-300 tests)

---

## Phase 1: EASY WINS - Full Implementations (4-6 hours, 20+ tests)

After stubs are working, implement full functionality:

### 1.1 ✅ COMPLETE - Fix break Return Value (15 minutes, 3 tests)

**Issue**: `break` with no arguments returns `false` instead of `nil`
**Fix**: Changed default break value from false to nil in compile_control.rb lines 256-260, 279
**Status**: ✅ Fixed - break now correctly returns nil
**Impact**: +3 tests (until_spec improved 18→21 passed)

### 1.2 ✅ COMPLETE - String Interpolation Bug (1 hour)

**Issue**: Interpolation in percent strings included extra "#" character:
```ruby
%(hey #{@ip})  # Expected: "hey xxx", Got: "hey #xxx"
```

**Root cause**: tokens.rb was adding "#" to buffer BEFORE checking for interpolation
**Fix**: Check for interpolation first, only add "#" to buffer if not followed by "{"
**Files**: tokens.rb (3 locations), quoted.rb (1 location)
**Status**: ✅ Fixed - all "hey #xxx" failures eliminated
**Commit**: a39b3ef
**Impact**: Fixes all #{} interpolation in percent strings

### 1.3 ✅ PARTIAL - Loop Control Issues (2-3 hours, 8+ tests)

**Issues**:
1. ~~`next` in modifier form doesn't work correctly~~ - Actually working, tests pass
2. ✅ `begin...end until condition` doesn't execute body at least once - FIXED

**Fix**: Modified compile_until in compile_control.rb (lines 191-228)
- Detect post-test loops by [:block, [], ...] pattern
- Extract body from body[2] (statements array)
- Generate: loop_label: body; if !cond goto loop_label

**Status**: ✅ Post-test loops fixed
**File**: compile_control.rb
**Files affected**: until_spec
**Impact**: Fixes specific semantic bug where `begin; body; end until cond` must execute body at least once

### 1.4 ⚠️ BLOCKED - Keyword Arguments / Hash Splatting (Est: 1-2 weeks, 60+ tests)

**Status**: Requires major compiler changes, significantly more complex than initially estimated

**Issue**: Methods with keyword arguments fail at runtime:
- `foo(a: 1, b: 2)` generates `[:call, :foo, [[:pair, [:sexp, :a], 1], [:pair, [:sexp, :b], 2]]]`
- `foo(**h)` generates `[:call, :foo, [[:hash_splat, h]]]`
- These `:pair` and `:hash_splat` AST nodes aren't in the keywords list
- `compile_args_nosplat` calls `compile_eval_arg` on them
- They fall through to line 1317 and are treated as method calls
- Results in: "undefined method 'hash_splat' for #<Object>"

**Required changes**:
1. Add `:pair` and `:hash_splat` to compiler keywords list
2. Implement `compile_pair` and `compile_hash_splat` methods
3. OR: Transform keyword args to hash in transform.rb before compilation
4. Handle `**nil`, `**{}`, and regular keyword arguments uniformly
5. Update argument passing conventions to support keyword arguments

**Files affected**:
- compiler.rb (keywords list, compile_exp dispatch)
- compile_calls.rb (argument compilation)
- transform.rb (possibly transform :pair/:hash_splat before compilation)

**Specs affected**: keyword_arguments_spec, hash_spec, def_spec, END_spec
**Impact**: ~60+ tests, but requires significant architectural work

### 1.5 Implement catch/throw Fully (2-3 hours, 18 tests)

After stub proves concept, implement proper non-local return mechanism
**Files**: lib/core/kernel.rb, compiler (similar to break/next handling)
**Impact**: throw_spec fully passes

### Phase 1 Total Impact
- **Time**: 4-6 hours (after Phase 0 complete)
- **Tests fixed**: 70+ additional tests
- **New pass rate**: ~35-40% (350-400 tests)

---

## Phase 2: MEDIUM DIFFICULTY (4-8 hours)

### 2.1 Hash Edge Cases (2-3 hours, 15 tests)

**Issues**:
1. Empty hash keys: `{=> value}` should create `{nil => value}`
2. `**nil` in hash literal should expand to `{}`
3. Missing `Hash#to_hash` for splatting

**Files affected**: hash_spec
**Impact**: +15 tests

### 2.2 BEGIN/END Blocks (4-6 hours, 14+ tests)

**Files affected**: BEGIN_spec (crashes), END_spec (14 failures)
**Impact**: +14 tests

### 2.3 Missing Utility Methods - Full Implementations (2-3 hours, 10+ tests)

Implement full versions of:
- `Object#instance_eval` - Evaluate block in object's context
- `Object#proc` - Create Proc from block
- Test-specific methods after investigation

**Impact**: +10-20 tests

### Phase 2 Total Impact
- **Time**: 8-12 hours
- **Tests fixed**: 40+ additional tests
- **New pass rate**: ~40-45% (400-450 tests)

---

## Phase 3: HARD - Lambda/Block Segfaults (1-2 weeks)

**Category B from crash analysis**: 16 specs crash in lambda/block execution

### Investigation Priority Order

**B1. Global Variable in Closure (3-5 hours)** - Highest priority common pattern
- **Symptoms**: Many specs crash at `rubyspec_helper.rb:744` during `$spec_shared_method = nil`
- **Specs**: loop, range, symbol, while
- **Root cause**: Global variable assignment from within closure/lambda
- **Investigation**:
  1. Check how global variables are accessed in closures
  2. Verify `__env__` doesn't interfere with global scope
  3. Test simple case: `1.times { $x = 42 }`

**B2. NULL Pointer Dereferencing (2-4 hours)** - Clear error pattern
- **Symptoms**: Crash at address `0x00000000` (NULL)
- **Specs**: block_spec, safe_navigator_spec, variables_spec
- **Root cause**: Uninitialized variable or bad pointer in block
- **Investigation**:
  1. Check closure environment allocation
  2. Verify all closure variables initialized
  3. Use valgrind to track uninitialized memory

**B3. Lambda Execution Crashes (5-10 hours)** - Complex debugging
- **Specs**: array_spec (line 205), case_spec (line 242), proc_spec (line 155)
- **Investigation**:
  1. Examine specific test lines that crash
  2. Create minimal reproducers
  3. Debug with gdb to find exact failure point

**B4. Invalid Memory Access (5-10 hours)** - Memory corruption
- **Symptoms**: Crashes at invalid addresses like `0x68726164`, `0x00000015`
- **Specs**: loop_spec, range_spec, symbol_spec
- **Investigation**:
  1. Run under valgrind to detect memory corruption
  2. Check array/string bounds
  3. Review garbage collector interaction

### Phase 3 Total Impact
- **Time**: 1-2 weeks
- **Specs fixed**: 16 specs
- **Tests fixed**: 150-200 tests
- **New pass rate**: ~55-65% (550-650 tests)

---

## Phase 4: VERY HARD - Startup Segfaults (1-2 weeks)

**Category C from crash analysis**: 5 specs crash before test code runs

**Specs**:
- class_spec.rb - Crash in `_start`
- metaclass_spec.rb - Crash in `_start`
- singleton_class_spec.rb - Crash in `_start`
- file_spec.rb - Crash loading rubygems.rb during spec_setup
- super_spec.rb - Crash in main() at line 799

**Investigation**:
1. Check class hierarchy initialization
2. Review global initialization order
3. Debug with gdb from `_start`
4. Check if static initializers cause issues

### Phase 4 Total Impact
- **Time**: 1-2 weeks
- **Specs fixed**: 5 specs
- **Tests fixed**: 50-100 tests
- **New pass rate**: ~60-70% (600-700 tests)

---

## Summary: Realistic Improvement Plan

### Recommended Execution Order

**Week 1: Quick Wins**
- Phase 0: Stub methods (2-4 hours) → 26-30% pass rate
- Phase 1: Full implementations (4-6 hours) → 35-40% pass rate
- **Total**: 6-10 hours → +200-240 tests

**Week 2: Medium Difficulty**
- Phase 2: Hash edges, BEGIN/END, utilities → 40-45% pass rate
- **Total**: 8-12 hours → +40 tests

**Week 3-4: Hard Debugging**
- Phase 3: Lambda/block segfaults → 55-65% pass rate
- **Total**: 1-2 weeks → +150-200 tests

**Week 5-6: Very Hard**
- Phase 4: Startup segfaults → 60-70% pass rate
- **Total**: 1-2 weeks → +50-100 tests

### Expected Outcomes

**Realistic near-term (1 week)**: 35-40% pass rate (350-400 tests)
**Optimistic mid-term (1 month)**: 55-65% pass rate (550-650 tests)
**Maximum achievable**: 80-85% pass rate (800-850 tests)

---

## Known Limitations (Cannot Fix - 632 tests)

These are fundamental architectural constraints:

1. **Regular Expressions Not Implemented** (507 failures, 65% of all failures)
2. **eval() Not Supported** (~100 failures, AOT compiler limitation)
3. **Float Type Not Implemented** (~17 failures)
4. **Command Execution Not Supported** (~8 failures, backticks/`%x{}`)

**Maximum achievable pass rate**: ~80-85% (800-850 tests) even with all bugs fixed

---

## Testing Commands

```bash
make selftest        # Must pass
make selftest-c      # Must pass
./run_rubyspec rubyspec/language/         # Language specs
make spec            # Custom specs
```

## References

- **KNOWN_ISSUES.md** - Detailed bug documentation
- **RUBYSPEC_CRASH_ANALYSIS.md** - Comprehensive crash categorization
- **DEBUGGING_GUIDE.md** - Debugging techniques
- **ARCHITECTURE.md** - System architecture
