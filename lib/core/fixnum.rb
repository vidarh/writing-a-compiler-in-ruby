# Fixnum class - ultra-minimal implementation
# All methods except 2 are now inherited from Integer
#
# Methods that MUST remain in Fixnum:
# - class: Returns Fixnum for compiler class identity checks
# - *: Multiplication (Integer version causes FPE during compilation)
#
# Methods now inherited from Integer (56+ methods):
# Comparison: <, >, <=, >=, <=>
# Arithmetic: +, -, /, %, div, divmod, mul, **, -@, +@
# Bitwise: &, |, ^, ~, <<, >>
# Conversion: to_s, to_i, to_int, to_f, chr, inspect, hash
# Query: zero?, even?, odd?, frozen?, allbits?, anybits?, nobits?
# Utility: abs, magnitude, ord, times, pred, succ, next
# Advanced: gcd, lcm, gcdlcm, ceildiv, digits, coerce, bit_length, size
# Helpers: __get_raw, ceil, floor, truncate, []
#
# Fixnum reduced from 535 lines (58 methods) to 47 lines (2 methods)!

class Fixnum < Integer

  def class
    Fixnum
  end

  # % removed - now inherited from Integer
  # Integer version includes Ruby semantics for sign handling

  # __get_raw removed - now inherited from Integer
  # Integer version handles both tagged fixnums and heap integers

  # <, >, <=, >=, <=>, - removed - now inherited from Integer
  # Integer versions handle both tagged fixnums and heap integers

  # * is CRITICAL - cannot be removed yet
  # Integer version causes FPE during compilation (needs investigation)
  def * other
    if !other.is_a?(Integer)
      other = other.to_int
    end
    %s(let (result) (assign result (mul (sar self) (sar other)))
      (__int (bitand result 0x7fffffff)))
  end

  # / removed - now inherited from Integer
  # Integer version uses __get_raw for both representations
end

# __int moved to integer_base.rb
