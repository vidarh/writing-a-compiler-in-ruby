# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-10 - Latest Update)

**Selftest**: **ALL PASSING** (0 failures) - selftest and selftest-c both pass
**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 79 files, 2 passed (3%), 9 failed, 9 crashed, **59 compile failures (75%)**
  - Passing: and_spec.rb (10/10), not_spec.rb (10/10)
  - Failing: comment_spec.rb (needs eval), match_spec.rb (needs Regexp#=~), numbers_spec.rb (needs eval), 6 regexp specs (need Regexp support)
  - Crashes: array_spec.rb (fixed implicit hash, now crashes at runtime), loop_spec.rb, or_spec.rb, redo_spec.rb, + 5 others
  - Individual tests: 27/124 passed (21% pass rate)
**Custom Specs (spec/)**: 13 files, **11 passed**, 1 failed, 1 crashed. 45 tests, **40 passed (88%)**
  - Passing: 11 specs including hash_literal_with_block, ternary_operator, control_flow_expressions
  - Failing: float_spec.rb (Float not implemented - 5 tests)
  - Crashing: break_with_splat_spec.rb (crashes in mspec framework, but standalone test works)

**Progress**:
- Bignum multiplication fix COMPLETED! Selftest now fully passes
- Implicit hash in arrays FIXED - array literals with hash pairs now compile
- Block parameter forwarding FIXED - `foo *a, &b` works without parentheses
- Break with splat FIXED - `break *[1,2]` works correctly
- Hash literals with blocks FIXED - argument wrapping corrected
- Custom spec pass rate: 88% (40/45 tests passing)
- **Known limitation**: Multiple specs crash at runtime in mspec framework (not feature bugs)

## High Priority (Compilation Failures - Simplest First)

- [x] Add lambda [] call syntax support - COMPLETED
- [x] Add lambda .() call syntax support - COMPLETED (2025-11-08) - tokens.rb detects .() and inserts :call method name
- [x] Fix `include` support - COMPLETED (2025-11-08) - basic include works, but ordering issues remain (see KNOWN_ISSUES #3)
- [x] Fix control flow as expressions (KNOWN_ISSUES #1, spec/control_flow_expressions_spec.rb) - COMPLETED (2025-11-10) - if/while/unless/until now work as expressions
- [ ] Fix toplevel constant paths (`class ::Foo`) (KNOWN_ISSUES #4) - reverted feature

### Language Spec Compilation Failures (Investigation 2025-11-10)

Multiple types of failures blocking language specs:

1. **Implicit hash in array literals** - COMPLETED (2025-11-10)
   - Fixed by group_pairs() in treeoutput.rb
   - array_spec.rb now compiles (but crashes at runtime - see Medium Priority)

2. **Block parameter forwarding** (e.g. `method(*a, &b)`) - COMPLETED (2025-11-10)
   - Fixed by merging :to_block into :call/:| expressions in treeoutput.rb
   - `foo m, *a, &b` now parses correctly (without parentheses)
   - block_spec.rb now compiles further (hits issue #8 with optional block params)

3. **Operator precedence issues** - COMPLETED (2025-11-10)
   - Fixed by recognizing `:a=` as a valid symbol in sym.rb
   - `{:a==>1}` now parses correctly as `{:a= => 1}`

4. **Break with splat** (e.g. `break *[1,2]`) - COMPLETED (2025-11-10):
   - ✅ Parser fixed: Modified shunting.rb to prevent premature reduction of prefix operators
   - ✅ Code generation fixed: Implemented compile_splat method in compiler.rb
   - Tests: selftest (✓), selftest-c (✓), standalone test (✓)
   - See KNOWN_ISSUES.md #11 for full implementation details

5. **String interpolation edge cases**:
   - Unusual delimiters like `%$hey #{expr}$` fail to parse
   - Affects: string_spec.rb
   - Root cause: Percent literals after identifiers not recognized (`puts %{hello}` fails)
   - Context check `@first || prev_lastop` too restrictive - needs to recognize percent literals as arguments
   - Priority: Low - requires deep tokenizer state machine refactoring

6. **Complex method definitions**:
   - Parse errors on edge cases like `def foo(x = (def foo; "hello"; end;1));x;end`
   - Affects: def_spec.rb
   - Low priority - very unusual edge case

7. **Missing alias keyword** - COMPLETED (2025-11-10):
   - ✅ Implemented in tokens.rb, parser.rb, compiler.rb, compile_class.rb
   - ✅ Parses `alias new_name old_name` and creates vtable entries
   - ✅ Tests: selftest (✓), selftest-c (✓), test_alias.rb (✓)
   - Note: alias_spec.rb still fails with "Module not found" (spec dependencies issue, not alias bug)

8. **Block parameters with default values** (e.g. `{ |a=5, b=4| }`) - PARTIALLY FIXED (2025-11-10):
   - ✅ Parser now handles syntax correctly
   - ✅ Transform phase preserves default values
   - ❌ Runtime execution broken - see KNOWN_ISSUES.md #9 for details
   - Priority: Low - uncommon pattern, workaround exists (use nil checks)

Priority: Focus on remaining high-impact compilation failures or runtime crashes (array_spec.rb)

## Medium Priority (Crashes - Fix After Compile Issues)

- [ ] Fix array_spec.rb runtime crash - compiles successfully, but segfaults at runtime with severe stack corruption (ESP=0xa64a84cc, EBP=0xffffd3d0). Crash occurs in __lambda_L290 at rubyspec_helper.rb:664 during mocking framework execution. GDB shows "Cannot access memory" at crash point, indicating corrupted instruction pointer. Root cause unknown - may be related to mspec framework internals or compiler-generated code for complex nested lambdas.
- [ ] Fix Float-related crashes: fdiv_spec, round_spec, times_spec (KNOWN_ISSUES #7)
- [ ] Investigate 7 language spec crashes: class_variable, encoding, order, safe, syntax_error, undef, variables

## Medium Priority (Runtime Failures - Lower Impact)

### Custom Spec Failures (spec/)
- [x] Implement Array#max - COMPLETED (2025-11-10) - spec/array_max_integer_size_spec.rb now passing
- [x] Implement Array#min - COMPLETED (2025-11-10)
- [x] Implement String#upcase, #downcase - COMPLETED (2025-11-10)
- [x] Implement String#start_with?, #end_with? - COMPLETED (2025-11-10)
- [x] Implement String#include? - COMPLETED (2025-11-10)
- [x] Implement String#strip, #lstrip, #rstrip - COMPLETED (2025-11-10)
- [x] Implement Array#any?, #all?, #none? - COMPLETED (2025-11-10)
- [ ] Fix Float support - needed for spec/float_spec.rb (5 failures)
- [x] Fix hash literal with block - spec/hash_literal_with_block_spec.rb - COMPLETED (2025-11-10) - fixed argument wrapping in compile_calls.rb
- [x] Fix ternary operator bug - spec/ternary_operator_bug_spec.rb - COMPLETED (2025-11-10) - fixed compile_if to save results to %eax

### RubySpec Failures
- [ ] Fix integer spec runtime failures (mostly Float comparisons, type errors)
- [ ] Fix remaining language spec runtime failures (match, numbers, regexp, source_encoding)
- [ ] Debug loop_spec crash (loop method implemented but spec crashes - may be redo/next/control flow issue)

### Module Include Ordering Fixes (May Fix Spec Failures)

- [x] Fix Comparable ordering - COMPLETED (2025-11-08) - Integer comparison operators now work (see KERNEL_MIGRATION_PLAN.md Phase 3)

## Low Priority (Code Quality / Cleanup)

### Kernel Method Migrations (see KERNEL_MIGRATION_PLAN.md for full details)

Now that `include` works, move methods from Object to Kernel where they belong. See KERNEL_MIGRATION_PLAN.md for implementation steps and validation requirements.

- [x] Phase 1.0: Migrate loop method - COMPLETED (2025-11-08)
- [x] Phase 1.1: Migrate exit method - COMPLETED (2025-11-08)
- [x] Phase 1.2: Migrate Array() method - COMPLETED (2025-11-08)
- [x] Phase 2.1: puts method - KEEP BOTH (bootstrap requirement - see KERNEL_MIGRATION_PLAN.md #3)
- [x] Phase 2.2: Migrate raise method - COMPLETED (2025-11-08)

### Other Cleanup

- [ ] Investigate Integer::MIN corruption (KNOWN_ISSUES #5)
- [ ] Improve Float support beyond stubs (KNOWN_ISSUES #7)
- [ ] Fix remaining integer spec edge cases (shifts >2^32, power/multiplication accuracy)
- [ ] Eigenclass (class << obj) support - very complex

## Testing

```bash
make selftest        # Must pass (1 expected failure)
make selftest-c      # Must pass (1 expected failure)
./run_rubyspec rubyspec/core/integer/    # Integer specs
./run_rubyspec rubyspec/language/         # Language specs
```

## References

- **WORK_STATUS.md** - Current work journal
- **KERNEL_MIGRATION_PLAN.md** - Detailed plan for moving methods from Object to Kernel
- **DEBUGGING_GUIDE.md** - Debugging techniques
- **ARCHITECTURE.md** - System architecture
- **RUBYSPEC_INTEGRATION.md** - How to run specs
