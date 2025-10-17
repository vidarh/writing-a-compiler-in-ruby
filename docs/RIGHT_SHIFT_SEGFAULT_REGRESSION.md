# Right Shift Spec Segfault Regression Analysis

## Summary

**Regression:** `right_shift_spec.rb` changed from running to completion (FAIL with wrong results) to SEGFAULT.

**Breaking Commit:** `a2c2301` - "Fix parser bug: negative numbers after newlines now parse correctly"

**Last Working Commit:** `b9a5da1` - (revert commit that temporarily fixed it)

## Timeline

```
d2f8905  ✅ right_shift_spec runs (7 passed, 32 failed, 7 skipped)
7406fc8  ✅ right_shift_spec runs
2936c55  ✅ right_shift_spec runs
893156b  ✅ (revert)
96cba2d  ✅ right_shift_spec runs (revert)
5d7db50  ❓ (test addition)
b9a5da1  ✅ right_shift_spec runs (revert)
a2c2301  ❌ right_shift_spec SEGFAULTS <<< BREAKING COMMIT
3dd07d2  ❌ right_shift_spec SEGFAULTS (HEAD)
```

## Symptom

At commit a2c2301 and later (including HEAD):
- `right_shift_spec.rb` segfaults when entering the "when m is a bignum or larger than int" context
- Segfault address: `0xffffffff` (invalid function pointer)
- Backtrace shows crash in lambda/proc call chain

At commits before a2c2301:
- `right_shift_spec.rb` runs to completion with test failures but no crash
- Output: "7 passed, 32 failed, 7 skipped (46 total)"

## Verification

### Test at working commit (b9a5da1):
```bash
git checkout b9a5da1
./run_rubyspec rubyspec/core/integer/right_shift_spec.rb
# Output: 7 passed, 32 failed, 7 skipped (46 total)
```

### Test at breaking commit (a2c2301):
```bash
git checkout a2c2301
./run_rubyspec rubyspec/core/integer/right_shift_spec.rb
# Output: Segmentation fault when entering "when m is a bignum" context
```

## Crash Location

From GDB backtrace:
```
Program received signal SIGSEGV, Segmentation fault.
0xffffffff in ?? ()
#0  0xffffffff in ?? ()
#1  0x565aef1b in __lambda_L277 () at rubyspec_temp_right_shift_spec.rb:67
#2  0x56572a84 in __method_Proc_call () at /app/rubyspec_helper.rb:522
```

The crash happens at an invalid address (0xffffffff), suggesting a corrupted function pointer or return address.

## Root Cause

The breaking commit a2c2301 modified the parser's handling of negative numbers after newlines. This change appears to have introduced a code generation bug that affects:
1. Bignum operations with negative values
2. Lambda/proc calling conventions
3. Or the interaction between these two

The spec that crashes uses patterns like:
- `(-1 >> bignum_value)`
- `(-bignum_value >> bignum_value)`

Where `bignum_value` returns 18446744073709551616 (real 2^64 value as of commit eb3d08b).

## Attempted Minimal Reproductions

**Note:** Multiple attempts to create standalone minimal test cases did NOT reproduce the segfault:

1. `test/right_shift_bignum_segfault.rb` - Direct bignum right shift operations
2. `test/bignum_shift_with_context.rb` - Simulating context blocks
3. `test/bignum_mult_before_hook.rb` - Simulating before :each hooks

All these tests RUN SUCCESSFULLY at both the working and breaking commits.

## Conclusion

**The segfault is triggered by a specific combination of:**
1. Parser changes in commit a2c2301 (negative number handling)
2. RubySpec test framework structure (lambdas, procs, before hooks)
3. Operations on large bignum values
4. Negative number literals in expressions

**The bug cannot be easily reproduced outside the full spec framework context**, suggesting it's related to:
- Code generation for complex nested lambda/proc structures
- Interaction between parser changes and closure compilation
- Stack corruption or calling convention issues in deeply nested contexts

## Recommendation

1. **Revert commit a2c2301** and related parser changes until the root cause is identified
2. **Investigate the parser changes** in a2c2301 to understand what code generation changed
3. **Compare assembly output** of the failing spec between b9a5da1 and a2c2301
4. **Add regression tests** once the fix is understood

## Related Files

- Breaking commit: a2c2301
- Affected spec: `rubyspec/core/integer/right_shift_spec.rb`
- Parser changes: Likely in `parser.rb`, `shunting.rb`, or `tokens.rb`
