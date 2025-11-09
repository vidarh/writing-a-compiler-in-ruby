# Compiler Work Status

**PURPOSE**: Journaling space for tracking ongoing work, experiments, and investigations.

## Current Session (2025-11-08)

**Status**: Active development - implementing quick wins from TODO list

**Recent Completions**:
1. ✅ Proc#[] method - lambda[] syntax now works (all tests pass)
2. ✅ Octal literal parsing - 0377 now correctly = 255 (octal)  
3. ⚠️  Object#loop method - works in methods, crashes in some specs

**Test Improvements**:
- Custom specs: 43% → 64% pass rate
- lambda_call_syntax_spec: 2/6 → 4/4 tests passing (100%)
- numbers_spec: 4/22 → 5/22 tests passing

**Next Tasks**:
- Investigate loop_spec crash (may be redo/next/control flow issue)
- Consider implementing lambda .() syntax (requires parser changes)
- Look at other runtime failures in language specs

## Update Protocol

After completing any task:
1. Run `make selftest-c` (MUST pass)
2. Commit changes with detailed message
3. Update this file with current status
4. Move completed details to git commit message

## Session 2025-11-09 (Continuation - Integer#size Implementation) ✅ COMPLETED

**GOAL**: Implement Integer#size to pass rubyspec/core/integer/size_spec.rb
**STATUS**: ✅ Complete - spec fully passes (2 passed, 0 failed)

**Implementation**:
```ruby
def size
  result = (self.bit_length + 7) / 8
  if result < 4
    4
  else
    result
  end
end
```

**Work Completed**:

1. **Integer#size implementation** ✅
   - Used `bit_length` method to calculate bytes needed
   - Formula: `(bit_length + 7) / 8` rounds up to nearest byte
   - Minimum size: 4 bytes (32-bit platform)
   - Works for both fixnums and bignums

2. **Created spec for failed Array#max approach** ✅
   - `spec/array_max_integer_size_spec.rb` - documents that `[4, x].max` approach failed
   - Reason: Array#max not implemented
   - Added task to TODO.md for future Array#max implementation

3. **Discovered and fixed platform_is guard bug** ✅
   - **Problem**: `platform_is c_long_size: 64` tests ran on 32-bit, causing failures
   - **Root Cause**: Hash literals passed to methods with blocks cause runtime error "undefined method 'pair'"
   - **Solution**: Modified `run_rubyspec` preprocessor to convert `platform_is c_long_size: 64` → `if false`
   - **Result**: 64-bit tests now skipped on 32-bit platform

4. **Documented hash literal + block bug** ✅
   - Created `spec/hash_literal_with_block_spec.rb` - demonstrates the bug
   - Added KNOWN_ISSUES #5: Hash literals as arguments with blocks
   - Error: "undefined method 'pair' for Object" when accessing hash
   - Impact: Prevents using hash arguments in platform guards

5. **Documentation updates** ✅
   - Added CRITICAL RULE to CLAUDE.md: Never delete failing specs
   - Updated KNOWN_ISSUES.md with hash literal bug (#5)
   - Updated TODO.md with Array#max task
   - Files created: 3 specs documenting bugs for future fixes

**Test Results**:
- Integer#size spec: 2 passed, 0 failed, 0 skipped ✅
- Custom specs: 3 new failing specs documenting bugs (expected to fail)

**Files Modified**:
- lib/core/integer.rb: Implemented size method (lines 3766-3773)
- run_rubyspec: Added preprocessing for platform_is c_long_size guards
- rubyspec_helper.rb: Attempted platform_is implementation (doesn't work due to hash bug)
- CLAUDE.md: Added CRITICAL RULE about never deleting failing specs
- docs/KNOWN_ISSUES.md: Added issue #5 (hash literals with blocks)
- docs/TODO.md: Added Array#max task

**Specs Created**:
- spec/array_max_integer_size_spec.rb - Documents Array#max not implemented
- spec/ternary_operator_bug_spec.rb - Documents ternary returning false
- spec/hash_literal_with_block_spec.rb - Documents hash + block runtime error

**Key Discoveries**:
- Hash literals can be passed to methods with blocks (compiles fine)
- But accessing the hash at runtime fails with "undefined method 'pair'"
- This is why platform guards had to be preprocessed out
- Ternary operator has a bug (returns false in some cases)

**Outcome**: ✅ Integer#size COMPLETE and passing all tests

## Session 2025-11-08 (Continued from previous context)

**Goal**: Continue working through TODO list after completing lambda .() and include support

**Work Completed**:

1. **Implemented Class#include? method** ✓
   - **Problem**: integer_spec.rb failing - "Integer includes Comparable" returned false
   - **Solution**: Implemented include? by checking vtable for module methods
   - **Approach**: Loop through vtable slots, check if module methods match class methods
   - **Bootstrap consideration**: Used s-expressions to avoid Array dependency during bootstrap
   - **Testing**: selftest ✓, selftest-c ✓, integer_spec 3/3 ✓
   - **Impact**: Integer specs improved from 30/67 → 31/67 files passing

2. **Investigated other integer spec failures**
   - size_spec: failures expected (32-bit vs 64-bit architecture)
   - try_convert_spec: failures due to limited exception support
   - minus_spec: failures due to Float comparison issues
   - lcm_spec: bignum arithmetic bugs with very large numbers
   - **Conclusion**: Most remaining failures require Float, exceptions, or complex bignum fixes

**Key Technical Decisions**:

1. **Class#include? implementation via vtable comparison**
   - **Why**: Simple, no runtime tracking needed, works during bootstrap
   - **How**: Check if module's vtable slots match class's vtable slots
   - **Limitation**: Approximation (class might independently define same methods)
   - **Good enough**: Passes specs, handles real-world use cases

2. **Bootstrap constraints prevent Ruby wrapper approach**
   - Initial attempt: Ruby method __do_include_module that tracks modules
   - Problem: Array not available when Object includes Kernel (bootstrap line 62 vs 75)
   - Solution: Avoid Array, use only s-expressions for include?

**Files Modified**:
- lib/core/class.rb: Implemented include? with vtable comparison (22 lines)
- compile_include.rb: Comment update

**Test Results**:
- Integer specs: 31/67 files passing (was 30/67), 360/568 tests passing (63%)
- selftest: PASS (1 expected failure)
- selftest-c: PASS (1 expected failure)

**Commits**:
- 997705b: "Implement Class#include? method for module introspection"

**Next Steps**:
- Primary blocker: Control flow as expressions (too complex for incremental work)
- Float-related failures require Float implementation
- Exception-related failures require proper exception support  
- Bignum arithmetic bugs require deep investigation

**Status**: Completed Class#include? implementation. No obvious quick wins remaining in integer specs. Most remaining issues require substantial work (Float, exceptions, control flow).


## Session 2025-11-08 Part 2: Language Spec Investigation

**Goal**: Explore language specs to find tractable issues after completing Class#include?

**Work Completed**:

1. **Investigated Language Specs** (66 files total)
   - **Passing** (2/66):
     - and_spec.rb: 10/10 tests ✓
     - not_spec.rb: 10/10 tests ✓
   - **Failing** (3/66):
     - comment_spec.rb: 0/1 (needs eval)
     - match_spec.rb: 2/12 (needs Regexp#=~, String#=~)
     - numbers_spec.rb: 5/22 (needs eval for complex/rational literals)
   - **Crashes** (5/66):
     - class_variable_spec.rb, encoding_spec.rb, loop_spec.rb, order_spec.rb, or_spec.rb
   - **Compilation Failures** (56/66 = 85%):
     - Most due to control flow as expressions (#1 KNOWN_ISSUES)
     - Examples:
       - `end.should` (while_spec.rb) - method call on `end` keyword
       - `def` as expression (case_spec.rb, def_spec.rb)
       - Block argument passing `&b` (block_spec.rb)
       - Hash/Array literal syntax issues
       - Missing file dependencies (file_spec.rb tries to require 'rubygems')

2. **Updated TODO.md** with accurate test counts:
   - Integer specs: 31/67 passing (46%, was 45%)
   - Language specs: 2/66 passing (3%)
   - Custom specs: 3/5 passing (71%)

**Key Findings**:

1. **Control flow as expressions is THE blocker**:
   - 56/66 language specs fail to compile
   - Primary cause: parser architecture doesn't support control structures going through shunting yard
   - Examples: `if...end.method`, `while...end.to_s`, `def...end[0]`

2. **Minor missing features** (would unlock a few specs):
   - Regexp#=~ and String#=~ (match_spec.rb)
   - eval support (comment_spec.rb, numbers_spec.rb - not feasible for AOT compiler)

3. **No easy wins in language specs**:
   - The 2 passing specs (and, not) are simple boolean operators
   - Everything else requires either control flow fix or substantial features

**Commits**:
- f9d55bf: "Update TODO with current test status: integer/language specs"

**Conclusion**:
Language specs confirm that control flow as expressions (#1 KNOWN_ISSUES) is the primary blocker for progress. Without fixing this architectural issue, we're limited to:
- Fixing individual integer spec failures (Float, exceptions, bignum)
- Implementing missing methods on existing classes
- Small bug fixes

The include support work is complete and working well.

**Status**: Investigation complete. No tractable language spec work without addressing control flow issue.

