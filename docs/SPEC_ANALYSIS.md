# Integer Spec Failure Analysis

## Summary
- Total: 68 spec files
- Passed: 7 (10%)
- Failed: 17 (25%)
- Segfault/Runtime: 22 (32%)
- Compile Fail: 22 (32%)

## COMPILE FAILURES (22 specs)

### Issue 1: tokens.rb:383 NoMethodError (10 specs)
**Error**: `undefined method '[]' for nil:NilClass` at tokens.rb:383

**Affected specs**:
- coerce_spec
- comparison_spec
- divide_spec
- div_spec
- downto_spec
- fdiv_spec
- remainder_spec
- (3 more to verify)

**Root cause**: Tokenizer bug with certain Ruby syntax patterns

### Issue 2: "Missing value in expression" (3 specs)
**Error**: `Missing value in expression / op: {pair/2 pri=5}` in treeoutput.rb:92

**Affected specs**:
- abs_spec (op: pair/2)
- magnitude_spec (op: pair/2)
- plus_spec (op: assign/2)

**Root cause**: Parser shunting yard algorithm issue with certain operators

### Issue 3: "Syntax error" in shunting (4 specs)
**Error**: `Syntax error. [{/0 pri=99}]` in shunting.rb:183

**Affected specs**:
- element_reference_spec
- exponent_spec
- modulo_spec
- pow_spec

**Root cause**: Unhandled operator precedence issue

### Issue 4: Parse error for do-block (1 spec)
**Error**: `Expected: 'end' for 'do'-block` in minus_spec

**Affected**: minus_spec

**Root cause**: Parser doesn't handle `class << obj; private def` inside do-block

### Issue 5: nil in get_arg (1 spec)
**Error**: `nil received by get_arg` (repeated)

**Affected**: chr_spec

**Root cause**: Argument processing receives nil

### Issue 6: Linker error (1 spec)
**Error**: `undefined reference to 'FloatDomainError'`

**Affected**: divmod_spec

**Root cause**: Missing FloatDomainError class constant

### Issue 7: multiply_spec, to_f_spec, upto_spec, round_spec
Need investigation - not captured in output

## SEGFAULTS (22 specs)

### Issue 1: Method missing Float#__get_raw (5 specs)
**Error**: `Method missing Float#__get_raw` → Floating point exception

**Affected specs**:
- gte_spec
- gt_spec
- lte_spec
- lt_spec
- right_shift_spec

**Root cause**: Float class missing __get_raw method for coercion

### Issue 2: Method missing Object#Integer (3 specs)
**Error**: `Method missing Object#Integer` → Floating point exception

**Affected specs**:
- ceildiv_spec
- ceil_spec
- floor_spec

**Root cause**: Missing Integer() conversion method

### Issue 3: Method missing Object#mock_int (1 spec)
**Error**: `Method missing Object#mock_int` → Floating point exception

**Affected**: digits_spec

**Root cause**: Missing mock_int helper in spec framework

### Issue 4: Method missing Mock#to_i (1 spec)
**Error**: `Method missing Mock#to_i` → Floating point exception

**Affected**: right_shift_spec

**Root cause**: Mock class missing to_i stub

### Issue 5: Plain segfaults (12 specs)
**Error**: Immediate segfault with no error message

**Affected specs**:
- bit_and_spec
- bit_length_spec
- bit_or_spec
- bit_xor_spec
- case_compare_spec
- denominator_spec
- equal_value_spec
- left_shift_spec
- numerator_spec
- rationalize_spec
- size_spec
- times_spec
- uminus_spec

**Root cause**: NEEDS GDB INVESTIGATION

## FAILURES (17 specs)

### Issue 1: Bitwise operations wrong (4 specs)
**Affected**:
- allbits_spec (0/11 passed) - Returns wrong true/false values
- anybits_spec (0/12 passed) - Returns wrong true/false values
- nobits_spec (0/12 passed) - Returns wrong true/false values
- complement_spec (0/7 passed) - Returns 0 instead of complement

**Root cause**: Wrong implementation of allbits?, anybits?, nobits?, ~ operator

### Issue 2: Bignum conversion broken (4 specs)
**Affected**:
- to_s_spec (6/21 passed) - Returns "1" instead of proper bignum string
- even_spec (4/6 passed) - Bignum even? fails
- odd_spec (3/5 passed) - Bignum odd? fails
- gcd/lcm/gcdlcm specs - Bignum edge cases

**Root cause**: Bignum representation and conversion issues

### Issue 3: ArgumentError not raised (4 specs)
**Affected**: gcd_spec, gcdlcm_spec, lcm_spec, to_r_spec

**Root cause**: Missing argument count validation

### Issue 4: Other failures
- constants_spec - Fixnum/Bignum constants should not exist
- zero_spec - Returns Fixnum class instead of Integer
- truncate_spec - Precision handling issues
- integer_spec, sqrt_spec, try_convert_spec - Missing class methods

## TOP 5 ISSUES BY IMPACT

### 1. Method missing Float#__get_raw (5 specs)
**Impact**: 5 SEGFAULT → FAIL/PASS
**Effort**: Low - stub method
**Priority**: HIGH

### 2. tokens.rb:383 NoMethodError (10+ specs)
**Impact**: 10+ COMPILE_FAIL → test
**Effort**: Medium - tokenizer bug
**Priority**: HIGH

### 3. Plain segfaults (12 specs)
**Impact**: 12 SEGFAULT → depends on root cause
**Effort**: Unknown - needs gdb
**Priority**: HIGH

### 4. Bitwise complement ~ operator (1 spec + enables other fixes)
**Impact**: 1 FAIL → PASS, unblocks other bitwise ops
**Effort**: Low - implement ~ operator
**Priority**: MEDIUM

### 5. Method missing Object#Integer (3 specs)
**Impact**: 3 SEGFAULT → FAIL/PASS
**Effort**: Low - stub method
**Priority**: MEDIUM

## Recommended Fix Order

1. **Stub Float#__get_raw** - Quick win, 5 specs improved
2. **Stub Object#Integer()** - Quick win, 3 specs improved
3. **Add FloatDomainError class** - Trivial fix, 1 spec compiles
4. **GDB investigation of plain segfaults** - Understand 12 specs
5. **Implement ~ operator** - Enables complement_spec to pass

After these 5, reassess based on findings.
