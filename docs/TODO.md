# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-15 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, **3 passed (4%)**, 12 failed, **17 crashed**, **47 compile failures (59%)**
**Custom Specs (spec/)**: 36 files, **24 passed (67%)**, 4 failed, 5 crashed, 3 compile failures. 82 tests, 68 passed (82%)

## High Priority (Language Spec Compilation Failures)

Focus on rubyspec/language/ compile failures blocking 51/79 specs (65%):

### Critical Blockers (Remaining 53 COMPILE FAIL specs)

**Quick Wins (Likely Simple Fixes)**:
- [x] **unless_spec** - ✅ FIXED - Handle nil in get_arg (compiler.rb:138), now PASSES 6/6 tests
- [x] **until end.should without parens** - ✅ FIXED - Removed parse_until from parse_defexp (parser.rb:488)
- [x] **Parenthesized break/next/return** - ✅ FIXED - Added nil value check before closing paren (shunting.rb:162-165)
  - Note: `break if condition` in assignment still fails (separate bug, see KNOWN_ISSUES #2)
- [x] **For loop with method call targets** - ✅ FIXED - Use shunting yard parser for loop variables (parser.rb:230,255)
  - Note: `for ... end.should` still fails (separate bug, similar to while end.should issue)

**High Priority (Affecting Multiple Specs)**:
- [x] **nil ClassScope** - ✅ FIXED (compile_class.rb) - break_spec, line_spec, file_spec now compile
- [ ] **Classes-in-lambdas runtime segfault** - Compiles but crashes (see KNOWN_ISSUES #3) - blocks break_spec runtime
- [ ] **Splat in assignment LHS** - Affects: next_spec, assignments_spec. See KNOWN_ISSUES #17
- [ ] **Hash spread operator `**`** - Affects: hash_spec, keyword_arguments_spec. See KNOWN_ISSUES #26. Parser treats ** as exponentiation, needs context-sensitive handling
- [ ] **Fixture loading** - file_spec, line_spec link failures (CodeLoadingSpecs fixtures need File methods)

**Medium Priority**:
- [x] **for...end method chaining** - ✅ FIXED - Added operator-based parsing, method chaining works
- [x] **Rescue in do...end blocks** - ✅ FIXED - Issues #25 and #28 resolved. spec/do_block_rescue_spec.rb passes 2/2
- [ ] **Lambda with default parameters** - Affects: lambda_spec. See KNOWN_ISSUES #9
- [ ] **String interpolation percent literals** - Affects: string_spec, heredoc_spec. Tokenizer refactor needed

### Control Flow Specs
- [x] **break_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - runtime segfault remains
- [ ] **next_spec.rb** - COMPILE FAIL (splat assignment error)
- [ ] **return_spec.rb** - COMPILE FAIL (unclosed block error)
- [ ] **redo_spec.rb** - CRASH (compiles, runtime crash)
- [ ] **loop_spec.rb** - CRASH (compiles, runtime crash)
- [x] **unless_spec.rb** - ✅ **PASSES 6/6** (was 5/6, fixed nil else-arm bug)

### Data Structure Specs
- [ ] **array_spec.rb** - CRASH (compiles, runtime crash in mspec framework)
- [ ] **hash_spec.rb** - COMPILE FAIL (hash spread operator ** - see KNOWN_ISSUES #26)
- [x] **range_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed by long method name fix) - runtime segfault

### Class/Module Specs
- [ ] **class_spec.rb** - COMPILE FAIL (nested class `class Foo::Bar`, defined?(::A) issues)
- [ ] **module_spec.rb** - COMPILE FAIL (nested module `module Foo::Bar`)
- [ ] **metaclass_spec.rb** - COMPILE FAIL (eigenclass/singleton class)
- [ ] **singleton_class_spec.rb** - COMPILE FAIL
- [ ] **class_variable_spec.rb** - CRASH

### Method/Block Specs
- [ ] **method_spec.rb** - COMPILE FAIL (keyword arg without value: `call(a:)`)
- [ ] **block_spec.rb** - CRASH (compiles, runtime segfault - likely KNOWN_ISSUES #3)
- [x] **proc_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed destructuring detection) - runtime segfault
- [x] **lambda_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed lambda without block + SpecEvaluate stub)
- [x] **yield_spec.rb** - ✅ COMPILES (now compiles with special globals fix)
- [x] **delegation_spec.rb** - ✅ COMPILES (now compiles with special globals fix)
- [ ] **keyword_arguments_spec.rb** - COMPILE FAIL
- [ ] **super_spec.rb** - COMPILE FAIL (infinite recursion issue - see KNOWN_ISSUES)

### Other Specs
- [ ] **alias_spec.rb** - COMPILE FAIL (Module not found - dependency issue, not alias bug)
- [ ] **assignments_spec.rb** - COMPILE FAIL
- [ ] **optional_assignments_spec.rb** - COMPILE FAIL
- [ ] **case_spec.rb** - COMPILE FAIL
- [ ] **if_spec.rb** - CRASH (compiles, runtime crash)
- [ ] **unless_spec.rb** - FAIL (compiles, 5/6 tests pass)
- [ ] **until_spec.rb** - COMPILE FAIL (until end.should without parens - see KNOWN_ISSUES #1)
- [ ] **while_spec.rb** - COMPILE FAIL (||= with paren expr - see KNOWN_ISSUES #2)
- [ ] **for_spec.rb** - COMPILE FAIL
- [ ] **constants_spec.rb** - COMPILE FAIL (nested class `class Foo::Bar`)
- [ ] **defined_spec.rb** - COMPILE FAIL (self::Constant static resolution issue)
- [x] **ensure_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed long method name bug) - runtime crash
- [ ] **rescue_spec.rb** - COMPILE FAIL (safe navigation in rescue clause `rescue => self&.var`)
- [ ] **retry_spec.rb** - ✅ COMPILES (was COMPILE FAIL) - FAILED (retry not implemented)
- [x] **throw_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed special global $!) - FAILED (catch/throw not implemented)
- [ ] **variables_spec.rb** - COMPILE FAIL
- [ ] **private_spec.rb** - COMPILE FAIL
- [ ] **send_spec.rb** - COMPILE FAIL
- [ ] **safe_navigator_spec.rb** - COMPILE FAIL
- [ ] **precedence_spec.rb** - COMPILE FAIL
- [ ] **pattern_matching_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)
- [ ] **numbered_parameters_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)

### Infrastructure/Meta Specs
- [ ] **BEGIN_spec.rb** - COMPILE FAIL
- [x] **END_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed $? special global) - FAILED (END blocks not implemented)
- [ ] **execution_spec.rb** - COMPILE FAIL
- [x] **file_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - link failure (fixture loading)
- [x] **line_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - link failure (fixture loading)
- [ ] **magic_comment_spec.rb** - COMPILE FAIL
- [ ] **predefined_spec.rb** - COMPILE FAIL
- [ ] **encoding_spec.rb** - CRASH
- [ ] **order_spec.rb** - CRASH
- [ ] **safe_spec.rb** - CRASH
- [ ] **undef_spec.rb** - CRASH

### Regexp Specs (All Require Regexp Support)
All regexp/ specs fail - Regexp not implemented. Low priority until core Regexp support added.

## Medium Priority (Runtime Crashes - After Compile Fixes)

- [ ] **Classes-in-lambdas segfault** - See KNOWN_ISSUES #3 - affects break_spec, line_spec, file_spec
- [ ] **times_spec.rb** (core/integer) - NOW COMPILES, crashes at runtime
- [ ] **or_spec.rb** (language) - NOW COMPILES, crashes at runtime
- [x] **unless_spec.rb** (language) - ✅ PASSES 6/6 tests (was 5/6, fixed nil else-arm bug)
- [ ] **array_spec.rb** (language) - Severe stack corruption in mspec framework
- [ ] **loop_spec.rb, redo_spec.rb** - Control flow crashes
- [ ] **7 other language crashes** - class_variable, encoding, order, safe, syntax_error, undef, variables

## Low Priority

- [ ] **Float support** - Needed for spec/float_spec.rb, some integer specs
- [ ] **Block parameters with default values** - See KNOWN_ISSUES #9 (runtime broken, parser works)
- [ ] **Toplevel constant paths** (`class ::Foo`) - See KNOWN_ISSUES #4 (reverted)
- [ ] **Eigenclass/singleton class** - Complex feature, affects metaclass/singleton specs
- [ ] **Integer::MIN corruption** - See KNOWN_ISSUES #5
- [ ] **Kernel method migrations** - See KERNEL_MIGRATION_PLAN.md

## Testing Commands

```bash
make selftest        # Must pass
make selftest-c      # Must pass
./run_rubyspec rubyspec/language/         # Language specs
./run_rubyspec rubyspec/core/integer/     # Integer specs
make spec            # Custom specs
```

## References

- **KNOWN_ISSUES.md** - Detailed bug documentation
- **KERNEL_MIGRATION_PLAN.md** - Object → Kernel method migration
- **DEBUGGING_GUIDE.md** - Debugging techniques
- **ARCHITECTURE.md** - System architecture
