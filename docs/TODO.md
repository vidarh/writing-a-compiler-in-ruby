# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-15 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, **3 passed (4%)**, 12 failed, **17 crashed**, **47 compile failures (59%)**
**Custom Specs (spec/)**: 36 files, **22 passed (61%)**, 4 failed, 5 crashed, 5 compile failures. 79 tests, 62 passed (78%)

**Recent Fixes (2025-11-15 Session 7)**:
- **✅ for...end method chaining** - For loops now support method chaining like while/until
  - Added "for" as :for_stmt operator in operators.rb (precedence 2)
  - Created parse_for_body() method that doesn't consume 'for' keyword
  - Added handler for :for_stmt in shunting.rb oper() method
  - Removed parse_for from parse_defexp chain
  - Modified rewrite_for() in transform.rb to return enumerable instead of nil
  - Transforms: `for x in arr; body; end` → `(tmp = arr; tmp.each { |x| body }; tmp)`
  - Result: `(for i in 1..3; end).class` => Range, method chaining works
  - Test: spec/for_end_method_chain_spec.rb - 2/3 tests pass (1 fails due to Range#== bug)
  - Test: selftest-c passes with 0 failures
  - Commits: d32ad49, a7a621f

**Recent Fixes (2025-11-15 Session 6 continuation)**:
- **✅ Multi-line lambda in it_behaves_like** - Fixed run_rubyspec sed rewrite
  - Changed it_behaves_like sed regex to not add `)` when line ends with `{`
  - Pattern: `s/^\([[:space:]]*\)it_behaves_like \(.*[^{]\)$/\1it_behaves_like(\2)/`
  - Multi-line lambdas like `it_behaves_like :foo, -> x {` no longer broken
  - Previous: `it_behaves_like(:foo, -> x {)` - broken syntax
  - Fixed: `it_behaves_like :foo, -> x {` - closing `)` added after `}`
  - Result: predefined_spec.rb line 794 parse error FIXED
  - Test: selftest passes with 0 failures
  - Commit: 8b7e079

- **✅ Hash symbol with => operator** - Fixed {:b=>true} parsing
  - Check if `=` is followed by `>` before consuming it as part of symbol (sym.rb:17-19)
  - Previous: `:b=>true` parsed as `[:callm, :b=, :>, true]` (setter symbol :b=, then > operator)
  - Fixed: `:b=>true` parses as `[:pair, :b, true]` (hash pair)
  - Setter symbols like `:foo=` still work correctly
  - Result: yield_spec.rb now **COMPILES** (was COMPILE FAIL with "Literal Hash must contain key value pairs")
  - Test: selftest passes with 0 failures
  - Commit: 86c8469

- **✅ Alias statement in blocks** - alias now works in do...end blocks
  - Added parse_alias to parse_defexp alternatives (parser.rb:482)
  - parse_exp calls parse_alias (line 790) for top-level statements
  - parse_defexp (used by blocks) was missing parse_alias
  - Result: `do; alias new_name old_name; end` now parses correctly
  - Test: alias_spec.rb parse error FIXED (now compile error - needs alias implementation)
  - Test: selftest passes with 0 failures
  - Commit: 7f878a3

**Recent Fixes (2025-11-15 Session 5)**:
- **✅ Lambda keyword without block in expression** - Supports lambda { lambda } syntax
  - Check if block present after :lambda_stmt operator (shunting.rb:131-145)
  - If no block: treat 'lambda' as method call, push :lambda value, set op = nil
  - Added null checks for op throughout shunting.rb (lines 150, 170, 172, 204, 217)
  - Result: `lambda { lambda }` now parses correctly - inner lambda is method call
  - Test: lambda_spec.rb now **COMPILES** (was COMPILE FAIL)
  - Test: selftest passes with 0 failures
  - Commit: ee0b734

- **✅ SpecEvaluate stub** - Fixed linker errors in lambda_spec, method_spec
  - Added SpecEvaluate class with desc attribute to rubyspec_helper.rb
  - Some specs use SpecEvaluate.desc to annotate test context
  - Result: lambda_spec.rb now links successfully (no undefined reference errors)
  - Commit: 71c496a

- **✅ Stabby lambda with default parameters** - Supports -> a=1 { a } syntax
  - Pass ["{", :do] as stop tokens when parsing stabby lambda bare parameters (parser.rb:442)
  - Check inhibit list before treating { as block argument (shunting.rb:143)
  - Prevents default values from consuming lambda body as block argument
  - Result: `-> a=foo() { a }` now parses correctly, not `foo() { a }`
  - Test: proc_spec.rb now **COMPILES** (was COMPILE FAIL, now CRASH)
  - Test: selftest passes with 0 failures
  - Commits: 0c887d1, 7483a07

- **✅ Proc parameter destructuring detection** - Fixed [:destruct, ...] parameter handling
  - Fixed transform.rb to check a[0] == :destruct, not a[1] (transform.rb:67-69)
  - Destructuring has form [:destruct, :a, :b] with :destruct at index 0
  - Other special params have form [:name, :rest] with type at index 1
  - Result: proc { |(a, b)| a + b } now compiles without "Arg.name must be Symbol" error
  - Test: proc_spec.rb now COMPILES (was COMPILE FAIL)
  - Test: selftest passes with 0 failures
  - Commit: 0c887d1

**Recent Fixes (2025-11-15 Session 4)**:
- **✅ Anonymous block forwarding** - Supports bare & in parameter lists (Ruby 3.1+)
  - Allow & without name: def foo(&); end, proc { |&| }
  - Added AMP to allowed prefixes without names (parser.rb:86)
  - Enables block forwarding without naming the block parameter
  - Test: block_spec.rb now **COMPILES** (was COMPILE FAIL)
  - Test: selftest passes with 0 failures
  - Commit: 5e8f9fb

- **✅ Fixed nested destructuring with special parameters**
  - Fixed destructuring to preserve nested structure (parser.rb:55)
  - Removed .flatten that was breaking |(a, b)| parsing
  - Fixed transform.rb to not add defaults to :rest/:block/:keyrest/:key/:keyreq/:destruct
  - Root cause: transform.rb was wrapping ALL args with [:default, :nil], even [:args, :rest]
  - This created invalid [[:args, :rest], :default, :nil] that function.rb rejected
  - Test: block_spec.rb now COMPILES
  - Test: selftest passes with 0 failures
  - Commit: 5e8f9fb

- **✅ Block parameter nested destructuring** - Supports |(a, b)| and |(a, b), c| syntax
  - Added check for '(' at start of parse_arglist to detect destructuring
  - Recursively parse nested parameters and wrap in [:destruct, ...] node
  - Supports mixed patterns: |(a, b), c| parses as ((destruct a b) c)
  - Result: [[1,2]].map { |(a, b)| a + b } now parses correctly
  - Test: block_spec.rb advances from line 720 → 934 (214 line jump!)
  - Note: Parser ready, compiler backend needs destructuring support
  - Test: selftest passes with 0 failures
  - Commit: cf7d37d, 01bed2f

- **✅ Made lambda an operator for method chaining** - lambda now supports .call, .inspect, etc.
  - Added lambda as :lambda_stmt operator (prefix, priority 2, arity 0)
  - Added :lambda_stmt handling in shunting.rb to parse block after keyword
  - Removed lambda from special-case keyword list (now uses operator path)
  - Result: `lambda do...end.call` works, nested lambdas work
  - Test: spec/method_def_in_do_block_spec.rb - 2/2 tests PASS ✓
  - Test: block_spec.rb advances from line 70 → 679 (609 line jump!)
  - Test: selftest passes with 0 failures
  - Commit: 74517b6

- **✅ Fixed method definitions inside do...end blocks** - def now allowed in block bodies
  - Added parse_def to parse_defexp alternatives
  - Allows method definitions inside lambda/proc blocks
  - Test: `lambda do; def helper; 42; end; helper; end` now works
  - Commit: 406e819

- **✅ Fixed do...end rescue/else/ensure support** - do...end blocks now support rescue like begin...end
  - Extracted parse_rescue_else_ensure() shared method for parsing rescue/else/ensure clauses
  - Updated parse_begin_body() to use shared method
  - Updated parse_block() to use shared method
  - Changed parse_rescue_else_ensure to call parse_defexp (uses shunting yard for expressions)
  - Result: `lambda do raise X; rescue X; 42 end` now compiles
  - Test: spec/do_block_rescue_spec.rb compiles (runtime exceptions need work)
  - Test: selftest passes with 0 failures
  - Commit: a3eb8f7

**Recent Fixes (2025-11-14 Session 3)**:
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
- [ ] **Rescue in do...end blocks** - Affects: block_spec. See KNOWN_ISSUES #25. Parser works, compiler doesn't handle :proc with rescue
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
- [ ] **block_spec.rb** - CRASH (compiles, runtime segfault - likely KNOWN_ISSUES #3)
- [x] **proc_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed destructuring detection) - runtime segfault
- [x] **lambda_spec.rb** - ✅ COMPILES (was COMPILE FAIL, fixed lambda without block + SpecEvaluate stub)
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
