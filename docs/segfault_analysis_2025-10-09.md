# Segfault Analysis - 2025-10-09

## Test Results by Category

### Category 1: Block Parameter Bug (PRIMARY CAUSE ~19-28 specs)
**Root Cause**: Block parameters (|x|, |key, values|) treated as method calls
**Confirmed**: Yes - test case shows "Method missing Object#x" for `[1,2,3].each do |x|`

**Specs using blocks directly**: times_spec, downto_spec, upto_spec, numerator_spec, rationalize_spec

**Specs using shared examples with blocks**: abs_spec, magnitude_spec, case_compare_spec, equal_value_spec, 
exponent_spec, ceil_spec, floor_spec, modulo_spec, divide_spec, multiply_spec, minus_spec, plus_spec, 
pow_spec, round_spec, chr_spec, lte_spec

### Category 2: Symbol Parsing for .send() (~1-2 specs)
**Root Cause**: Symbol `:-@` parsed incorrectly as `:-` + `@`
**Confirmed**: uminus_spec - "Method missing Object#@" when calling `.send(:-@)`
**Workaround**: Direct `-x` works fine
**Affected**: uminus_spec.rb

### Category 3: Missing/Broken Method Implementations
**bit_length_spec**: Method exists but returns wrong values (always 32)
**ceildiv_spec**: Method exists but has logic bugs, also crashes on Rational literal `6/5r`
**size_spec**: Method exists (returns 4), segfault likely from bignum tests using `**`
**to_f_spec**: ✅ PARTIALLY FIXED - method added but returns integer, not Float

### Category 4: Lambda/Proc Related (needs more investigation)
**Specs using lambda**: allbits, anybits, nobits, bit_and, bit_or, bit_xor, and 13+ others
**Note**: Compiler HAS lambda support, need to identify specific lambda syntax causing issues

### Category 5: Other Missing Methods
- Float#** (exponentiation on floats) - needed by multiple specs
- Rational literal syntax `6/5r` - parser doesn't recognize this

## Quick Win Opportunities (Ranked)

1. **FIX bit_length**: Method exists but stub always returns 32
   - Impact: 1 spec (bit_length_spec.rb)
   - Difficulty: LOW - just needs proper implementation
   
2. **FIX ceildiv**: Logic bugs in existing implementation
   - Impact: 1 spec (ceildiv_spec.rb) 
   - Difficulty: LOW - fix algorithm, skip Rational tests

3. **FIX :-@ symbol parsing**: Allow `:-@` as valid symbol
   - Impact: 1 spec (uminus_spec.rb)
   - Difficulty: MEDIUM - tokenizer/parser change

4. **INVESTIGATE lambda specs more carefully**: Determine exact failure mode
   - Impact: 19 specs
   - Difficulty: UNKNOWN - need to test what specific lambda syntax fails

## Not Quick Wins (Complex)

1. **Block parameter bug**: Requires parser/compiler changes
   - Impact: 19-28 specs
   - Difficulty: HIGH

2. **Full Float support**: Needs FPU code generation
   - Impact: Multiple specs
   - Difficulty: HIGH

3. **Rational literal syntax**: Parser extension needed
   - Impact: Few specs
   - Difficulty: MEDIUM
