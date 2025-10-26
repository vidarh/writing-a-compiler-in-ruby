# Operator Precedence Bug: Bitwise OR (|) and Addition (+)

## Problem

The compiler incorrectly evaluates expressions with bitwise OR (`|`) and addition (`+`) operators.

**Expected behavior** (Ruby spec): `|` has lower precedence than `+`
- Expression `a | b + c` should parse as `a | (b + c)`

**Actual behavior** (compiler bug): `|` evaluated before `+`  
- Expression `a | b + c` parses as `(a | b) + c`

## Evidence

Test case: `0xffff | bignum_value + 0xf0f0` where `bignum_value = 2^64`

| Method | Result | Expected |
|--------|--------|----------|
| Stored first | 18446744073709617151 ✓ | 18446744073709617151 |
| Inline expression | 18446744073709678831 ✗ | 18446744073709617151 |
| MRI Ruby | 18446744073709617151 ✓ | 18446744073709617151 |

Difference: 61680 = 0xf0f0 (the addition operand)

## Test Case

```ruby
def bignum_value(n = 0)
  18446744073709551616 + n
end

# Correct: Store intermediate result
b = bignum_value + 0xf0f0
result1 = 0xffff | b  # => 18446744073709617151 ✓

# Bug: Inline expression
result2 = 0xffff | bignum_value + 0xf0f0  # => 18446744073709678831 ✗
```

## Impact

- bit_or_spec.rb line 10 failure
- Likely affects other bitwise operator specs with complex expressions
- Does NOT affect bitwise OR implementation itself (which is correct)

## Workaround

Store intermediate arithmetic results in variables before bitwise operations.

## Root Cause

Parser/compiler operator precedence table incorrect for bitwise operators.
Needs investigation in `parser.rb` or `operators.rb`.
