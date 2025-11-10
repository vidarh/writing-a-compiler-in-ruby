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
**Custom Specs (spec/)**: 10 files, **10 passed**, 0 failed, 0 compile fail. 41 tests, **41 passed (100%)**
  - All specs passing!

**Progress**: Bignum multiplication fix COMPLETED! Selftest now fully passes. Custom spec pass rate: 100%!

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

2. **Block parameter forwarding** (e.g. `method(*a, &b)`):
   - Error: "Expression did not reduce to single value (2 values on stack)"
   - Affects: block_spec.rb, likely others
   - Issue: Compiler doesn't handle `&block` parameter forwarding in method calls
   - Root cause: `&block` syntax generates two values on the value stack instead of one

3. **Operator precedence issues** - COMPLETED (2025-11-10)
   - Fixed by recognizing `:a=` as a valid symbol in sym.rb
   - `{:a==>1}` now parses correctly as `{:a= => 1}`

4. **Break with splat** (e.g. `break *[1,2]`):
   - Error: "Expression did not reduce to single value"
   - Affects: break_spec.rb
   - Issue: Similar to block forwarding - splat in break generates multiple stack values

5. **String interpolation edge cases**:
   - Unusual delimiters like `%$hey #{expr}$` fail to parse
   - Affects: string_spec.rb
   - Issue: Parser doesn't handle all string delimiter variants

6. **Complex method definitions**:
   - Parse errors on edge cases like `def foo(x = (def foo; "hello"; end;1));x;end`
   - Affects: def_spec.rb
   - Low priority - very unusual edge case

7. **Missing alias keyword**:
   - `alias` keyword not implemented
   - Affects: alias_spec.rb

Priority: Address block parameter forwarding (#2) next as it likely affects multiple specs

## Medium Priority (Crashes - Fix After Compile Issues)

- [ ] Fix array_spec.rb runtime crash - now compiles after implicit hash fix, but segfaults at runtime
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
- [ ] Fix hash literal with block - spec/hash_literal_with_block_spec.rb "undefined method 'pair'" (2 failures) - complex parser bug
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
