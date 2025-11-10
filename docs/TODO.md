# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-10 - Updated)

**Integer Specs**: 67 files, 31 passed (46%), 31 failed, 5 crashed. 568 tests, 360 passed (63%)
**Language Specs**: 66 files, 2 passed (3%), 3 failed, 5 crashed, **56 compile failures (85%)**
  - Passing: and_spec.rb (10/10), not_spec.rb (10/10)
  - Failing: comment_spec.rb (needs eval), match_spec.rb (needs Regexp#=~), numbers_spec.rb (needs eval)
**Custom Specs (spec/)**: 9 files, 5 passed, 4 failed, 0 compile fail. 42 tests, 27 passed, 15 failed (64%)
  - Passing: integer_size_spec.rb, lambda_call_syntax_spec.rb, lambda_dot_paren_spec.rb, ternary_operator_spec.rb, control_flow_expressions_spec.rb, ternary_operator_bug_spec.rb
  - Failing: array_max_integer_size_spec.rb (needs Array#max), float_spec.rb (needs Float), hash_literal_with_block_spec.rb (undefined method 'pair')

**Critical**: 56 language spec compilation failures still block most progress.

## High Priority (Compilation Failures - Simplest First)

- [x] Add lambda [] call syntax support - COMPLETED
- [x] Add lambda .() call syntax support - COMPLETED (2025-11-08) - tokens.rb detects .() and inserts :call method name
- [x] Fix `include` support - COMPLETED (2025-11-08) - basic include works, but ordering issues remain (see KNOWN_ISSUES #3)
- [x] Fix control flow as expressions (KNOWN_ISSUES #1, spec/control_flow_expressions_spec.rb) - COMPLETED (2025-11-10) - if/while/unless/until now work as expressions
- [ ] Fix toplevel constant paths (`class ::Foo`) (KNOWN_ISSUES #4) - reverted feature

## Medium Priority (Crashes - Fix After Compile Issues)

- [ ] Fix Float-related crashes: fdiv_spec, round_spec, times_spec (KNOWN_ISSUES #7)
- [ ] Investigate 7 language spec crashes: class_variable, encoding, order, safe, syntax_error, undef, variables

## Medium Priority (Runtime Failures - Lower Impact)

### Custom Spec Failures (spec/)
- [ ] Implement Array#max - needed for spec/array_max_integer_size_spec.rb (6 failures)
- [ ] Fix Float support - needed for spec/float_spec.rb (5 failures)
- [ ] Fix hash literal with block - spec/hash_literal_with_block_spec.rb "undefined method 'pair'" (2 failures)
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
