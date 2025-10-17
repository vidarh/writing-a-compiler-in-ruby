# Regression Analysis: Spec Failure Status Changes

## Summary

Between commit d2f8905 and HEAD, 3 specs regressed from **[PASS]** to **[FAIL]**:
1. `constants_spec.rb`
2. `digits_spec.rb`
3. `gcdlcm_spec.rb`

**Root Cause:** Change in `print_spec_results` exit code logic in `rubyspec_helper.rb`

## The Regression

### At commit d2f8905:
```ruby
def print_spec_results
  exit(1) if $spec_failed > 0
end
```
- Specs with 0 failures and only skipped tests → exit(0) → marked as [PASS]

### At HEAD:
```ruby
def print_spec_results
  exit(1) if $spec_failed > 0 || $spec_skipped > 0
end
```
- Specs with 0 failures but skipped tests → exit(1) → marked as [FAIL]

## Affected Specs

All three affected specs have NO actual assertions - all tests are skipped:

### constants_spec.rb
- Tests for `Fixnum` and `Bignum` constants
- Both tests skip with "is no longer defined (NO ASSERTIONS)"
- Result: 0 passed, 0 failed, 2 skipped
- d2f8905: [PASS] (exit code 0)
- HEAD: [FAIL] (exit code 1)

### digits_spec.rb
- Similar pattern - all tests skipped due to missing functionality
- d2f8905: [PASS]
- HEAD: [FAIL]

### gcdlcm_spec.rb
- Similar pattern - all tests skipped
- d2f8905: [PASS]
- HEAD: [FAIL]

## Test Case

```ruby
# test/skipped_tests_exit_code.rb
# This demonstrates the regression

$spec_passed = 0
$spec_failed = 0
$spec_skipped = 2

def print_spec_results
  puts
  total = $spec_passed + $spec_failed + $spec_skipped
  puts "#{$spec_passed} passed, #{$spec_failed} failed, #{$spec_skipped} skipped (#{total} total)"
  exit(1) if $spec_failed > 0 || $spec_skipped > 0  # Current behavior
end

print_spec_results
```

### Expected behavior at d2f8905:
- Exit code: 0 (spec marked as PASS)

### Actual behavior at HEAD:
- Exit code: 1 (spec marked as FAIL)

## Impact Assessment

This is **NOT a real regression in functionality** - it's a change in test framework behavior:

1. **No code broke** - the 3 specs still have the exact same test results
2. **Classification changed** - specs with only skipped tests now count as failures
3. **Metrics changed**:
   - d2f8905: 5 PASS, 37 FAIL, 25 SEGFAULT
   - HEAD: 2 PASS, 40 FAIL, 25 SEGFAULT
   - Net change: -3 PASS, +3 FAIL (but same actual test results)

## Recommendation

**This change appears intentional** - marking specs with all tests skipped as failures provides better signal about missing functionality.

### Options:
1. **Keep current behavior** - Skipped tests indicate missing features, should be tracked as failures
2. **Revert change** - Go back to allowing all-skipped specs to pass
3. **Add new status** - Create [SKIP] status for specs with 0 passed and 0 failed

My recommendation: **Keep current behavior**. The new classification is more accurate - specs that cannot run any assertions represent missing functionality and should not be counted as "passing".

## Verification

```bash
# Test at d2f8905
git checkout d2f8905
./run_rubyspec rubyspec/core/integer/constants_spec.rb
echo "Exit code: $?"  # Returns 0

# Test at HEAD
git checkout master
./run_rubyspec rubyspec/core/integer/constants_spec.rb
echo "Exit code: $?"  # Returns 1
```

Both produce identical output:
```
0 passed, 0 failed, 2 skipped (2 total)
```

But exit codes differ due to changed logic in `print_spec_results`.
