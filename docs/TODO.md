# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-11 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, 2 passed (3%), 11 failed, 12 crashed, **54 compile failures (68%)** - IMPROVED
**Custom Specs (spec/)**: 13 files, **11 passed**, 1 failed, 1 crashed. 45 tests, **40 passed (88%)**

**Recent Fixes (Session Summary)**:
- Fixed heredoc followed by method chain tokens.rb line 689-690
- Fixed keywords in parentheses shunting.rb line 201-204
- Fixed heredoc after method names tokens.rb line 578 - **Major impact: 60→54 compile failures (-10%)**
- Added ScratchPad stub for test framework
- **Result**: if_spec.rb now compiles and runs (11/13 tests pass)
- **Note**: 5 other specs now compile but have runtime bugs (not parser wins)
- Fixed `unless` inside `do` blocks shunting.rb line 202-208 - **unless_spec.rb now compiles**

## High Priority (Language Spec Compilation Failures)

Focus on rubyspec/language/ compile failures blocking 59/79 specs:

### Critical Blockers (Remaining 54 COMPILE FAIL specs)

**Actual Error Patterns Found** (see docs/spec_status_investigation.md):
- [x] **Expected 'end' for 'do'-block with unless** - FIXED for unless_spec. Still affects: execution_spec (backticks), predefined_spec (rescue in block)
- [ ] **Missing value in expression** - Affects: until_spec, while_spec (complex expressions in parentheses)
- [ ] **nil ClassScope** - Affects: break_spec, singleton_class_spec. See KNOWN_ISSUES #16
- [ ] **For loop with global variables** - Affects: for_spec. Error on `for @$spec_var in arr`
- [ ] **Splat in assignment LHS** - Affects: next_spec, assignments_spec. See KNOWN_ISSUES #17
- [ ] **Hash spread operator `**`** - Affects: hash_spec, keyword_arguments_spec

**Lower Priority**:
- [ ] **Lambda with default parameters** - Affects: lambda_spec. See KNOWN_ISSUES #9
- [ ] **Missing dependency stubs** - Affects: file_spec, line_spec, return_spec

### Control Flow Specs
- [ ] **break_spec.rb** - COMPILE FAIL (nil ClassScope error)
- [ ] **next_spec.rb** - COMPILE FAIL (splat assignment error)
- [ ] **return_spec.rb** - COMPILE FAIL (unclosed block error)
- [ ] **redo_spec.rb** - CRASH (compiles, runtime crash)
- [ ] **loop_spec.rb** - CRASH (compiles, runtime crash)

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
- [ ] **if_spec.rb** - COMPILE FAIL
- [ ] **unless_spec.rb** - COMPILE FAIL
- [ ] **until_spec.rb** - COMPILE FAIL
- [ ] **while_spec.rb** - COMPILE FAIL
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
- [ ] **file_spec.rb** - COMPILE FAIL
- [ ] **line_spec.rb** - COMPILE FAIL
- [ ] **magic_comment_spec.rb** - COMPILE FAIL
- [ ] **predefined_spec.rb** - COMPILE FAIL
- [ ] **encoding_spec.rb** - CRASH
- [ ] **order_spec.rb** - CRASH
- [ ] **safe_spec.rb** - CRASH
- [ ] **undef_spec.rb** - CRASH

### Regexp Specs (All Require Regexp Support)
All regexp/ specs fail - Regexp not implemented. Low priority until core Regexp support added.

## Medium Priority (Runtime Crashes - After Compile Fixes)

- [ ] **times_spec.rb** (core/integer) - NOW COMPILES, crashes at runtime
- [ ] **or_spec.rb** (language) - NOW COMPILES, crashes at runtime
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
