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

  def % other
    %s(assign r (callm other __get_raw))
    %s(assign m (mod (sar self) r))
    %s(if (eq (ge m 0) (lt r 0))
         (assign m (add m r)))
    %s(__int m)
  end

  # __get_raw removed - now inherited from Integer
  # Integer version handles both tagged fixnums and heap integers

  # < removed - now inherited from Integer
  # Integer version uses __cmp which handles all representation combinations

  def > other
    %s(if (gt (sar self) (callm other __get_raw)) true false)
  end

  def <= other
    %s(if (le (sar self) (callm other __get_raw)) true false)
  end

  def >= other
    %s(if (ge (sar self) (callm other __get_raw)) true false)
  end

  def <=> other
    return nil if !other.is_a?(Numeric)
    if self > other
      return 1
    end
    if self < other
      return -1
    end
    return 0
  end

  def - other
    %s(let (result) (assign result (sub (sar self) (callm other __get_raw)))
      (__int (bitand result 0x7fffffff)))
  end

  def * other
    if !other.is_a?(Integer)
      other = other.to_int
    end
    %s(let (result) (assign result (mul (sar self) (sar other)))
      (__int (bitand result 0x7fffffff)))
  end

  def / other
    if !other.is_a?(Integer)
      other = other.to_int
    end
    %s(__int (div (sar self) (sar other)))
  end
end

# __int moved to integer_base.rb
