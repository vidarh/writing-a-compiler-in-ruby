# Fixnum class - ultra-minimal implementation
# All methods are now inherited from Integer
#
# Fixnum is deprecated in Ruby 2.4+, unified with Integer
# For compatibility with rubyspecs, Fixnum.class now returns Integer
#
# Methods now inherited from Integer (57+ methods):
# Comparison: <, >, <=, >=, <=>
# Arithmetic: +, -, *, /, %, div, divmod, mul, **, -@, +@
# Bitwise: &, |, ^, ~, <<, >>
# Conversion: to_s, to_i, to_int, to_f, chr, inspect, hash
# Query: zero?, even?, odd?, frozen?, allbits?, anybits?, nobits?
# Utility: abs, magnitude, ord, times, pred, succ, next
# Advanced: gcd, lcm, gcdlcm, ceildiv, digits, coerce, bit_length, size
# Helpers: __get_raw, ceil, floor, truncate, []
#
# Fixnum reduced from 535 lines (58 methods) to 36 lines (0 methods)!

class Fixnum < Integer
  # No methods needed - everything inherited from Integer
  # In Ruby 2.4+, Fixnum.class returns Integer (Fixnum/Bignum unified)
end
