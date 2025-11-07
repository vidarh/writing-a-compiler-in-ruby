# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Test Status (2025-11-07)

**Integer Specs**: 67 files, 30 passed (45%), 34 failed, 3 crashed. 593 tests, 373 passed (62%)
**Language Specs**: 79 files, 2 passed (2%), 10 failed, 7 crashed, **60 compile failures (76%)**

**Critical**: 60 language spec compilation failures block most progress.

## High Priority (Compilation Failures - Simplest First)

- [ ] Fix ternary operator bug - variable condition returns `false` instead of else value (KNOWN_ISSUES #2, spec/ternary_operator_bug.rb)
- [ ] Add lambda .() call syntax support (KNOWN_ISSUES #6, spec/lambda_call_syntax.rb) - blocks lambda_spec
- [ ] Fix control flow as expressions (KNOWN_ISSUES #1) - **PRIMARY BLOCKER** - affects ~40+ language specs
- [ ] Fix toplevel constant paths (`class ::Foo`) (KNOWN_ISSUES #4) - reverted feature

## Medium Priority (Crashes - Fix After Compile Issues)

- [ ] Fix Float-related crashes: fdiv_spec, round_spec, times_spec (KNOWN_ISSUES #7)
- [ ] Investigate 7 language spec crashes: class_variable, encoding, order, safe, syntax_error, undef, variables

## Medium Priority (Runtime Failures - Lower Impact)

- [ ] Fix integer spec runtime failures (mostly Float comparisons, type errors)
- [ ] Fix remaining 10 language spec runtime failures (loop, match, numbers, regexp, source_encoding)

## Low Priority (Complex / Lower Payoff)

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
- **DEBUGGING_GUIDE.md** - Debugging techniques
- **ARCHITECTURE.md** - System architecture
- **RUBYSPEC_INTEGRATION.md** - How to run specs
