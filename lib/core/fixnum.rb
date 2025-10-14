# Fixnum class - minimal implementation with only critical methods
# All other methods are inherited from Integer
#
# Critical methods that MUST be defined here:
# - class: Returns Fixnum for compiler class identity checks
# - %: Modulo operator (used during compilation)
# - __get_raw: Extracts raw value from tagged fixnum
# - <, >, <=, >=, <=>: Comparison operators
# - -, *, /: Core arithmetic operators
#
# All other methods (48+) are inherited from Integer, including:
# to_s, hash, inspect, chr, to_i, zero?, ceil, floor, [], !=, !,
# div, divmod, mul, **, &, |, ^, ~, <<, >>, -@, +@, abs, magnitude,
# ord, times, pred, succ, next, frozen?, even?, odd?, allbits?,
# anybits?, nobits?, bit_length, size, to_int, to_f, truncate,
# gcd, lcm, gcdlcm, ceildiv, digits, coerce

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
