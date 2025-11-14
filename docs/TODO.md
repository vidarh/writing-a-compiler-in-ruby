# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-14 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, **1 passed (1%)**, 1 failed, 23 crashed, **54 compile failures (68%)** - baseline from Nov 12
**Custom Specs (spec/)**: 16 files, **14 passed**, 2 failed. Tests document bugs with minimal reproductions.

**Recent Fixes (2025-11-14)**:
- **✅ Fixed begin as prefix operator** - begin blocks now support method chaining like if/while/until
  - Added "begin" as operator in operators.rb (:begin_stmt, priority 2)
  - Handle :begin_stmt in shunting.rb prefix position by calling parse_begin_body
  - Created parse_begin_body method (doesn't consume begin keyword, like parse_if_body)
  - Removed parse_begin from parse_defexp chain (parser.rb:462)
  - Removed begin from [:for, :lambda, :def] special keyword list (shunting.rb:250)
  - Fixed compile_rescue to accept optional else_body parameter (4th arg)
  - Result: `begin...end.inspect` and `x = begin...end.method` now work correctly
  - **Bonus**: unless_spec.rb now PASSES (6/6 tests) - was compile failure before
  - Test: selftest and selftest-c pass with 0 failures
  - Commit: 1bdb613

**Recent Fixes (2025-11-12 Session 3)**:
- **✅ Fixed unless/if with nil else-arm** - Empty unless/if bodies now return nil correctly
  - Added special case in get_arg (compiler.rb:138) to handle Ruby nil like true/false
  - Was treating nil as string constant, generating label address instead of nil value
  - Result: unless_spec.rb now **PASSES all 6/6 tests** (was 5/6)
  - Test: selftest and selftest-c pass with 0 failures

**Recent Fixes (2025-11-12 Session 2)**:
- **✅ Fixed regression in break with argument** - Narrowed nil-value fix to parentheses only
  - Restricted fix to only apply to `()`, not blocks `{}` or arrays `[]` (shunting.rb:164)
  - Result: break_spec.rb compiles again, both `(break)` and `{ break 1 }` work correctly
  - Test: selftest passes, break_spec returns to CRASH (runtime) from COMPILE FAIL
- **✅ Fixed for loop with method call targets** - For loops now accept lvalue expressions
  - Changed parser.rb:230,255 to use shunting yard parser with [:in, COMMA] inhibit
  - Allows `for obj.attr in array`, `for obj[i] in array` patterns
  - Result: for_spec.rb compiles past line 143 (was failing with "Expected: 'in' keyword")
  - Test: selftest passes, for loops with method calls parse correctly
- **✅ Fixed parenthesized break/next/return** - Control flow keywords now work inside parentheses
  - Added check in shunting.rb:162-165 to provide nil value to prefix operators before closing paren
  - Result: `a ||= (break)`, `a = (next)`, `a = (return)` all compile successfully
  - Note: `break if condition` in assignment still fails (documented in KNOWN_ISSUES #2)
  - Test: spec/or_assign_paren_expr_spec.rb now compiles
- **✅ Fixed until end.should without parens** - All four control flow keywords now work with end.should
  - Removed parse_until from parse_defexp (parser.rb:488)
  - Deleted dead code: parse_while, parse_until, parse_if_unless functions
  - Refactored: Merged parse_while_body/parse_until_body → parse_while_until_body(type)
  - Both while and until now work identically - only as operators, not as statements
  - Result: if/unless/while/until all support end.should without parens (spec/all_control_flow_end_should_spec.rb)
- **Fixed while end.should chaining** - while loops now support method chaining on end keyword
  - Removed src.unget(token) in shunting.rb, created parse_while_body/parse_until_body
  - Result: while end.should works (spec/while_end_no_paren_spec.rb passes)
- **Created bug reproduction specs** - Isolated remaining parser bugs:
  - spec/until_end_should_spec.rb - ✅ FIXED, now passes
  - spec/or_assign_paren_expr_spec.rb - ||= with complex paren expression fails
- **Previous session**: nil ClassScope fix (52→51 compile failures total)

## High Priority (Language Spec Compilation Failures)

Focus on rubyspec/language/ compile failures blocking 51/79 specs (65%):

### Critical Blockers (Remaining 51 COMPILE FAIL specs)

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
- [ ] **Hash spread operator `**`** - Affects: hash_spec, keyword_arguments_spec. Context-sensitive parsing needed
- [ ] **Fixture loading** - file_spec, line_spec link failures (CodeLoadingSpecs fixtures need File methods)

**Medium Priority**:
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
- [ ] **hash_spec.rb** - COMPILE FAIL
- [ ] **range_spec.rb** - COMPILE FAIL

### Class/Module Specs
- [ ] **class_spec.rb** - COMPILE FAIL
- [ ] **module_spec.rb** - COMPILE FAIL
- [ ] **metaclass_spec.rb** - COMPILE FAIL (eigenclass/singleton class)
- [ ] **singleton_class_spec.rb** - COMPILE FAIL
- [ ] **class_variable_spec.rb** - CRASH

### Method/Block Specs
- [ ] **method_spec.rb** - COMPILE FAIL
- [ ] **block_spec.rb** - COMPILE FAIL
- [ ] **proc_spec.rb** - COMPILE FAIL
- [ ] **lambda_spec.rb** - COMPILE FAIL
- [ ] **yield_spec.rb** - COMPILE FAIL
- [ ] **delegation_spec.rb** - COMPILE FAIL
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
- [ ] **constants_spec.rb** - COMPILE FAIL
- [ ] **defined_spec.rb** - COMPILE FAIL
- [ ] **ensure_spec.rb** - COMPILE FAIL
- [ ] **rescue_spec.rb** - COMPILE FAIL
- [ ] **retry_spec.rb** - COMPILE FAIL
- [ ] **throw_spec.rb** - COMPILE FAIL
- [ ] **variables_spec.rb** - COMPILE FAIL
- [ ] **private_spec.rb** - COMPILE FAIL
- [ ] **send_spec.rb** - COMPILE FAIL
- [ ] **safe_navigator_spec.rb** - COMPILE FAIL
- [ ] **precedence_spec.rb** - COMPILE FAIL
- [ ] **pattern_matching_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)
- [ ] **numbered_parameters_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)

### Infrastructure/Meta Specs
- [ ] **BEGIN_spec.rb** - COMPILE FAIL
- [ ] **END_spec.rb** - COMPILE FAIL
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
