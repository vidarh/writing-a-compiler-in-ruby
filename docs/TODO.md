# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## CRITICAL Code Quality Issues

**CRITICAL**: Remove all `instance_variable_get` usage in compile_class.rb
- **Files**: compile_class.rb lines 52, 76, 77
- **Why CRITICAL**: `instance_variable_get` is ABSOLUTELY FORBIDDEN per CLAUDE.md
- **Locations**:
  - Line 52: `current.instance_variable_get(:@superclass)` - walking superclass chain
  - Lines 76-77: `global_scope.instance_variable_get(:@next)` - traversing scope chain
- **Fix Required**: Add proper accessor methods to the relevant classes instead of bypassing encapsulation
- **Priority**: MUST be fixed before any other non-critical work

## Test Status (2025-11-20 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, **3 passed (4%)**, 25 failed, **36 crashed (46%)**, **15 compile failures (19%)**
  - Test pass rate: 16% (157/973 individual tests passing) - **STABLE**
  - Passing specs: and_spec, not_spec, unless_spec
  - Recent fixes:
    - ✅ Fixed nested destructuring assignment (commit 47f7cb9)
    - ✅ Fixed closure environment corruption of :deref nodes (commit b8d257e)
    - ✅ Fixed :deref closure rewriting regression (commit b9ecc40)
  - Main blockers: constants_spec/metaclass_spec (linker errors), safe_navigator_spec (closure bug), variables_spec (anonymous splat)
**Custom Specs (spec/)**: 37 files, **25 passed (68%)**, 4 failed, 5 crashed, 3 compile failures. 86 tests, 72 passed (84%)

## High Priority (Language Spec Compilation Failures)

**Status Update (2025-11-18)**: All 29 compile failures investigated and categorized. See **COMPILE_FAILURES_SUMMARY.md** and **MINIMAL_SPECS_STATUS.md**.
- 18 specs with verified minimal test cases in spec/
- 11 specs with complex compiler bugs requiring deep investigation
- Prioritized by impact (specs affected) and estimated difficulty

### Priority 1: High Impact, Fixable (4-7 specs affected each)

1. **Keyword Argument Shorthand** - Issue #36 (4 specs) - **PARTIALLY FIXED**
   - Files: hash_spec, def_spec, method_spec, keyword_arguments_spec
   - Status: Hash literal syntax `{a:}`, `{a:, b:, c:}` now works ✓ (commit 3b8cd1f)
   - Remaining: hash_spec still fails with "Arg.name must be Symbol" - see KNOWN_ISSUES #47
   - Impact: Blocks basic hash and method call features
   - Test: spec/keyword_arg_shorthand_hash_spec.rb
   - Difficulty: Medium - Parser expands `{a:}` to `{a: a}` ✓, closure rewrite bug blocks hash_spec

2. **Global Namespace Class/Module Definition** - ✅ **FIXED**
   - Files: metaclass_spec, private_spec, singleton_class_spec
   - Status: Class definitions `class ::A` fixed (commit 1b47b62)
   - Status: Module definitions `module ::A` fixed (see KNOWN_ISSUES #48)
   - Test: spec/metaclass_assembly_error_spec.rb - PASSES
   - private_spec now compiles (runtime failures for missing Object#methods)

3. **Closure Environment Link Errors** - Compiler Bug (3 specs) - **HIGH**
   - Files: for_spec, send_spec, super_spec
   - Error: `undefined reference to __env__` and `__closure__`
   - Impact: Advanced closure scenarios broken
   - Tests: spec/for_closure_link_error_spec.rb, spec/send_closure_link_error_spec.rb
   - Difficulty: Hard - Compiler generates references but doesn't emit symbols

### Priority 2: Medium Impact (2-3 specs each)

4. **Splat with Begin Block** - Issue #45 - ✅ **FIXED** (commit ce239f1)
   - Files: assignments_spec, optional_assignments_spec
   - Status: `*begin...end` parsing now works correctly
   - Fix: begin blocks now parse regardless of waiting prefix operators
   - Remaining: Both specs still fail with nested destructuring assignment errors
   - Test: spec/array_index_splat_begin_spec.rb
   - Difficulty: Medium - Parser doesn't handle begin in array index

5. **Nested Constant Assignment in Closures** - Issue #46 (3 specs)
   - Files: constants_spec, module_spec, precedence_spec
   - Error: "Expected an argument on left hand side" - `A::B::C = value` in closures
   - Test: spec/module_nested_const_spec.rb
   - Difficulty: Hard - Compiler doesn't recognize nested const as lvalue

6. **Control Flow Edge Cases** (2 specs)
   - Files: until_spec, while_spec
   - Errors: Ternary+next, parenthesized break
   - Tests: spec/until_ternary_next_spec.rb, spec/while_parenthesized_break_spec.rb
   - Difficulty: Medium - Parser doesn't handle specific combinations

### Priority 3: Low Impact but Fixable (1 spec each)

7. **Safe Navigation Operator** - Feature Missing (1 spec) - **FIXED**
   - File: safe_navigator_spec.rb
   - Status: Fully implemented (commit afd66d2)
   - `&.` operator now works: returns nil if receiver is nil
   - Test: spec/safe_navigator_spec.rb - PASSES

8. **Regex After Semicolon** - Issue #38 (1 spec) - **DEFERRED**
   - File: case_spec.rb
   - Error: `/a/` after `;` parsed as division
   - Test: spec/regex_after_semicolon_spec.rb
   - Difficulty: Hard - Architecture issue (tokenizer doesn't know parser state)

9. **Parser Superclass Atom Requirement** - Issue #2 (1 spec)
   - File: class_spec.rb
   - Error: `class Foo < ""` requires identifier
   - Test: spec/class_superclass_atom_spec.rb
   - Difficulty: Easy - Parser should accept expressions

10. **Anonymous Splat Assignment** (1 spec)
    - File: variables_spec.rb
    - Error: `* = value` not recognized
    - Test: spec/anonymous_splat_assignment_spec.rb
    - Difficulty: Easy - Parser doesn't accept `*` as assignment target

11. **Regex Interpolation with Nested Regex** (1 spec)
    - File: regexp/encoding_spec.rb
    - Error: `/#{/./}/` parse error
    - Test: spec/regexp_encoding_block_error_spec.rb
    - Difficulty: Medium - Tokenizer confused by nested regex

### Priority 4: Complex Compiler Bugs (Deep Investigation Required)

12. **Global Variable Scope in require** (1 spec)
    - File: return_spec.rb
    - Error: `require $spec_filename` - variable not resolved
    - Test: spec/return_global_var_spec.rb
    - Difficulty: Hard - Compiler or require implementation issue

13. **Duplicate Symbol Definitions** (1 spec)
    - File: predefined_spec.rb
    - Error: `symbol __method_Object_method_missing is already defined`
    - Difficulty: Hard - Large file, method redefinition bug

14. **Symbol Expression Reduction** (1 spec)
    - File: symbol_spec.rb
    - Error: `%w{'!' '!=' '!~'}` - expression reduction error
    - Test: spec/symbol_expression_reduction_error_spec.rb
    - Difficulty: Hard - Shunting yard bug with quotes

15. **Register Allocator Division by Zero** (1 spec)
    - File: regexp/escapes_spec.rb
    - Error: regalloc.rb:332 divided by 0
    - Difficulty: Very Hard - Deep compiler bug in register allocation

16. **Heredoc Parsing** (1 spec)
    - File: heredoc_spec.rb
    - Error: Unterminated heredoc (tokenizer edge case)
    - Difficulty: Medium - Specific heredoc syntax bug

17. **Pattern Matching** (1 spec) - **OUT OF SCOPE**
    - File: pattern_matching_spec.rb
    - Note: Ruby 2.7+ feature, target is Ruby 2.5

### Recommended Attack Order

**Phase 1: Easy Wins (10-14 specs fixed)**
- Start with #9 (superclass atom) and #10 (anonymous splat) - simple parser fixes
- Then tackle #1 (keyword arg shorthand) - 4 specs, medium difficulty
- Consider #11 (regex interpolation) if time permits

**Phase 2: Medium Impact (4-6 specs fixed)**
- Fix #4 (splat+begin) and #6 (control flow edge cases) - parser improvements
- Attempt #7 (safe navigation) if feeling ambitious

**Phase 3: Hard Bugs (3-6 specs fixed)**
- Address #2 (global namespace class) - assembly generation bug
- Tackle #3 (closure environment) if needed - complex compiler bug
- Consider #5 (nested const in closures) - hard lvalue recognition

**Phase 4: Deep Investigation**
- Items #12-16 require significant debugging time
- Consider deferring until Phase 1-3 complete

### Old Critical Blockers (Completed)

**Quick Wins (COMPLETED)**:
- [x] **unless_spec** - ✅ FIXED - Handle nil in get_arg (compiler.rb:138), now PASSES 6/6 tests
- [x] **until end.should without parens** - ✅ FIXED - Removed parse_until from parse_defexp (parser.rb:488)
- [x] **Parenthesized break/next/return** - ✅ FIXED - Added nil value check before closing paren (shunting.rb:162-165)
  - Note: `break if condition` in assignment still fails (separate bug, see KNOWN_ISSUES #2)
- [x] **For loop with method call targets** - ✅ FIXED - Use shunting yard parser for loop variables (parser.rb:230,255)
  - Note: `for ... end.should` still fails (separate bug, similar to while end.should issue)

**High Priority (Affecting Multiple Specs)**:
- [x] **nil ClassScope** - ✅ FIXED (compile_class.rb) - break_spec, line_spec, file_spec now compile
- [x] **Hash spread operator `**`** - ✅ FIXED - Added context-sensitive `**` operator, Hash#merge, Hash#==. spec/hash_spread_spec.rb passes 3/3
- [x] **Regex literal tokenization** - ✅ FIXED (tokens.rb:475-515) - Fixed division vs regex detection. spec/regex_tokenization_spec.rb passes 4/4. Reduced compile failures from 47 to 41
- [ ] **Keyword argument shorthand `{a:}`** - CRITICAL: Affects hash_spec, method_spec. See KNOWN_ISSUES #36. Parser doesn't expand `{a:}` to `{a: a}`
- [ ] **Classes-in-lambdas runtime segfault** - Compiles but crashes (see KNOWN_ISSUES #3) - blocks break_spec runtime
- [x] **Splat in assignment LHS** - ✅ FIXED - Implemented in rewrite_destruct(). next_spec now compiles (runtime errors remain)
- [ ] **Fixture loading** - file_spec, line_spec link failures (CodeLoadingSpecs fixtures need File methods)

**Medium Priority**:
- [x] **for...end method chaining** - ✅ FIXED - Added operator-based parsing, method chaining works
- [x] **Rescue in do...end blocks** - ✅ FIXED - Issues #25 and #28 resolved. spec/do_block_rescue_spec.rb passes 2/2
- [ ] **Lambda with default parameters** - Affects: lambda_spec. See KNOWN_ISSUES #9
- [x] **String interpolation percent literals** - ✅ PARTIALLY FIXED - Interpolation now works, `$` and `@` delimiters allowed
  - See PERCENT_LITERAL_REFACTORING_PLAN.md for remaining cleanup work
  - TODO: Phase 1 - Review escape handling in quoted.rb against string_spec
  - TODO: Phase 2 - Delegate all percent parsing to quoted.rb
  - TODO: Phase 3 - Remove code duplication between tokens.rb and quoted.rb

### Control Flow Specs
- [x] **break_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - runtime segfault remains
- [x] **next_spec.rb** - ✅ COMPILES (was splat assignment error, now fixed) - runtime errors remain
- [ ] **return_spec.rb** - COMPILE FAIL (unclosed block error)
- [ ] **redo_spec.rb** - CRASH (compiles, runtime crash)
- [ ] **loop_spec.rb** - CRASH (compiles, runtime crash)
- [x] **unless_spec.rb** - ✅ **PASSES 6/6** (was 5/6, fixed nil else-arm bug)

### Data Structure Specs
- [x] **array_spec.rb** - ✅ COMPILES (was COMPILE FAIL regression, fixed %w interpolation handling) - CRASH (runtime segfault)
- [ ] **hash_spec.rb** - COMPILE FAIL (keyword arg shorthand `{a:}` - see KNOWN_ISSUES #36)
- [x] **range_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed by long method name fix) - runtime segfault
- [x] **string_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed underscore delimiter exclusion) - runtime status TBD

### Class/Module Specs
- [ ] **class_spec.rb** - COMPILE FAIL (nested class `class Foo::Bar`, defined?(::A) issues)
- [ ] **module_spec.rb** - COMPILE FAIL (nested module `module Foo::Bar`)
- [ ] **metaclass_spec.rb** - COMPILE FAIL (eigenclass/singleton class)
- [ ] **singleton_class_spec.rb** - COMPILE FAIL
- [ ] **class_variable_spec.rb** - CRASH

### Method/Block Specs
- [ ] **method_spec.rb** - COMPILE FAIL (keyword arg shorthand `call(a:)` - see KNOWN_ISSUES #36)
- [ ] **block_spec.rb** - CRASH (compiles, runtime segfault - likely KNOWN_ISSUES #3)
- [x] **proc_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed destructuring detection) - runtime segfault
- [x] **lambda_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed lambda without block return statement in shunting.rb) - runtime status TBD
- [x] **yield_spec.rb** - ✅ COMPILES (now compiles with special globals fix)
- [x] **delegation_spec.rb** - ✅ COMPILES (now compiles with special globals fix)
- [ ] **keyword_arguments_spec.rb** - COMPILE FAIL (likely keyword arg shorthand - see KNOWN_ISSUES #36)
- [ ] **super_spec.rb** - COMPILE FAIL (infinite recursion issue - see KNOWN_ISSUES)

### Other Specs
- [x] **alias_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed with alias runtime + global vars) - CRASH (runtime issue)
- [ ] **assignments_spec.rb** - COMPILE FAIL
- [ ] **optional_assignments_spec.rb** - COMPILE FAIL
- [ ] **case_spec.rb** - COMPILE FAIL (regex literal `/pattern/` parsed as division - see KNOWN_ISSUES #35)
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
- [x] **private_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed with global vars) - CRASH (runtime issue)
- [ ] **send_spec.rb** - COMPILE FAIL
- [ ] **safe_navigator_spec.rb** - COMPILE FAIL
- [ ] **precedence_spec.rb** - COMPILE FAIL
- [ ] **pattern_matching_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)
- [ ] **numbered_parameters_spec.rb** - COMPILE FAIL (Ruby 2.7+ feature)

### Infrastructure/Meta Specs
- [x] **BEGIN_spec.rb** - ✅ COMPILES (now compiles with special globals fix) - CRASH (BEGIN blocks not implemented)
- [x] **END_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed $? special global) - FAILED (END blocks not implemented)
- [x] **execution_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed with %x{} support) - FAILED (tests fail)
- [x] **file_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - link failure (fixture loading)
- [x] **line_spec.rb** - ✅ COMPILES (was nil ClassScope, now fixed) - link failure (fixture loading)
- [x] **magic_comment_spec.rb** - ✅ COMPILES (now compiles with special globals fix) - CRASH (shared not implemented)
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
