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

  def __get_raw
    %s(sar self)
  end

  def zero?
    %s(if (eq self 1) true false)
  end
  
  def to_i
    self
  end

  # FIXME: Incomplete - for integers, ceil just returns self unless precision is negative
  def ceil(prec=0)
    self
  end

  # FIXME: Stub - for integers, floor just returns self unless precision is negative
  def floor(prec=0)
    self
  end

  # FIXME
  # Bit access
  def [] i
    1
  end

  def to_s(radix=10)
    if radix < 2 || radix > 36
      STDERR.puts("ERROR: Invalid radix #{radix.inspect} - must be between 2 and 36")
      1/0
    else
      out = ""
      n = self
      neg = self < 0
      if neg
        n = 0 - n
      end
      digits = "0123456789abcdefghijklmnopqrstuvwxyz"
      while n != 0
        r = n % radix
        out << digits[r]
        break if n < radix
        n = n / radix
      end
      if out.empty?
        out = "0"
      elsif neg
        out << "-"
      end
      out.reverse
    end
  end

  def hash
    self
  end

  def inspect
    to_s
  end

  def chr
    %s(let (buf)
         (assign buf (__alloc_leaf 2))
         (snprintf buf 2 "%c" (sar self))
       (__get_string buf)
     )
  end

  def + other
    # Mask result to keep it in 31-bit signed range (30 bits + sign)
    %s(let (result) (assign result (add (sar self) (callm other __get_raw)))
      (__int (bitand result 0x7fffffff)))
  end

  def - other
    # Mask result to keep it in 31-bit signed range (30 bits + sign)
    %s(let (result) (assign result (sub (sar self) (callm other __get_raw)))
      (__int (bitand result 0x7fffffff)))
  end

  
  def <= other
    %s(if (le (sar self) (callm other __get_raw)) true false)
  end

  def == other
    if other.nil?
      return false 
    end
    return false if !other.is_a?(Numeric)
    %s(if (eq (sar self) (callm other __get_raw)) true false)
  end

  # FIXME: I don't know why '!' seems to get an argument...
  def ! *args
    false
  end

  def != other
    return true if !other.is_a?(Numeric)
    other = other.to_i
    %s(if (ne (sar self) (callm other __get_raw)) true false)
  end

  def < other
    %s(if (lt (sar self) (callm other __get_raw)) true false)
  end

  def > other
    %s(if (gt (sar self) (callm other __get_raw)) true false)
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

  def div other
    %s(__int (div (sar self) (sar other)))
  end

  def divmod other
    [self / other, self % other]
  end

  def mul other
    %s(__int (mul (sar self) (sar other)))
  end

  # These two definitions are only acceptable temporarily,
  # because we will for now only deal with integers

  def * other
    %s(__int (mul (sar self) (sar other)))
  end

  def / other
    %s(__int (div (sar self) (sar other)))
  end

  # FIXME: Stub - actual exponentiation implementation needed
  def ** other
    1
  end

  # Bitwise AND
  def & other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitand (callm self __get_raw) other_raw))
    else
      if other.respond_to?(:coerce)
        ary = other.coerce(self)
        if ary.is_a?(Array)
          a = ary[0]
          b = ary[1]
          a & b
        else
          STDERR.puts("TypeError: coerce must return [x, y]")
          nil
        end
      else
        STDERR.puts("TypeError: Integer can't be coerced into Integer")
        nil
      end
    end
  end

  # Bitwise OR
  def | other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitor (callm self __get_raw) other_raw))
    else
      if other.respond_to?(:coerce)
        ary = other.coerce(self)
        if ary.is_a?(Array)
          a = ary[0]
          b = ary[1]
          a | b
        else
          STDERR.puts("TypeError: coerce must return [x, y]")
          nil
        end
      else
        STDERR.puts("TypeError: Integer can't be coerced into Integer")
        nil
      end
    end
  end

  # Bitwise XOR
  def ^ other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitxor (callm self __get_raw) other_raw))
    else
      if other.respond_to?(:coerce)
        ary = other.coerce(self)
        if ary.is_a?(Array)
          a = ary[0]
          b = ary[1]
          a ^ b
        else
          STDERR.puts("TypeError: coerce must return [x, y]")
          nil
        end
      else
        STDERR.puts("TypeError: Integer can't be coerced into Integer")
        nil
      end
    end
  end

  # Bitwise NOT: flips all bits
  # For two's complement: ~n = -n-1
  def ~
    -(self + 1)
  end

  # Left shift: self << other
  # Shift left by 'other' bits
  def << other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      # Use sar to get numeric values from tagged integers
      # Note: sall/sarl are compiled with first arg as shift amount
      # Mask to 31 bits before tagging to prevent overflow (keeps 1 bit for tag)
      %s(__int (bitand (sall other_raw (sar self)) 0x7fffffff))
    else
      STDERR.puts("TypeError: Integer can't be coerced")
      nil
    end
  end

  # Right shift: self >> other
  # Arithmetic right shift by 'other' bits
  def >> other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      # Use sar to get numeric values from tagged integers
      # Note: sall/sarl are compiled with first arg as shift amount
      %s(__int (sarl other_raw (sar self)))
    else
      STDERR.puts("TypeError: Integer can't be coerced")
      nil
    end
  end

  # Unary minus
  def -@
    # Mask result to keep it in 31-bit signed range (30 bits + sign)
    %s(let (result) (assign result (sub 0 (sar self)))
      (__int (bitand result 0x7fffffff)))
  end

  # Unary plus (returns self)
  def +@
    self
  end

  # Absolute value
  def abs
    if self < 0
      -self
    else
      self
    end
  end

  # Alias for abs
  def magnitude
    abs
  end

  def ord
    self
  end
  
  def times
    if !block_given?
      return IntegerEnumerator.new(self)
    end
    i = 0
    while i < self
      yield i
      i +=1
    end
    self
  end

  def pred
    self - 1
  end

  def succ
    self + 1
  end

  # FIXME: Alias for succ
  def next
    self + 1
  end

  def frozen?
    true
  end

  # FIXME: Stub - actual implementation needed
  def even?
    self % 2 == 0
  end

  # FIXME: Stub - actual implementation needed
  def odd?
    (self % 2) != 0
  end

  # FIXME: Stub - actual implementation needed
  def allbits?(mask)
    self & mask == mask
  end

  # FIXME: Stub - actual implementation needed
  def anybits?(mask)
    self & mask != 0
  end

  # FIXME: Stub - actual implementation needed
  def nobits?(mask)
    self & mask == 0
  end

  # FIXME: Stub - returns bytes, not bits; actual implementation needed
  def bit_length
    # This is wrong - should return number of bits needed to represent the number
    # For now just return 32
    32
  end

  # FIXME: Stub - actual implementation needed
  def size
    4  # 32-bit integers = 4 bytes
  end

  def to_int
    self
  end

  # Convert integer to Float
  # FIXME: Stub - returns self as-is; proper implementation would convert to actual float
  def to_f
    self
  end

  # FIXME: Stub - for integers, truncate just returns self
  def truncate(ndigits=0)
    self
  end

  # Euclidean algorithm for GCD
  def gcd(other)
    a = self
    b = other

    # Make both positive
    if a < 0
      a = -a
    end
    if b < 0
      b = -b
    end

    # Euclidean algorithm
    while b > 0
      t = b
      b = a % b
      a = t
    end
    a
  end

  # LCM using GCD
  def lcm(other)
    return 0 if self == 0
    return 0 if other == 0
    a = self
    b = other
    if a < 0
      a = -a
    end
    if b < 0
      b = -b
    end
    g = gcd(other)
    (a / g) * b
  end

  # Return both GCD and LCM
  def gcdlcm(other)
    [gcd(other), lcm(other)]
  end

  # FIXME: Stub - actual ceildiv implementation needed
  # Ceiling division: divide and round towards positive infinity
  # ceildiv(a, b) returns the smallest integer >= a/b
  def ceildiv(other)
    # Convert other to integer if it responds to to_int (handles Rational, etc.)
    # This is the proper place to do type coercion, not in __get_raw
    if other.respond_to?(:to_int)
      other = other.to_int
    end

    # Handle division by converting to proper formula
    # For positive divisor: (a + b - 1) / b
    # For negative divisor: a / b (truncates towards zero, which is ceiling for negative results)
    # But we need to handle signs properly

    quotient = self / other
    remainder = self % other

    # If there's a remainder and quotient should round up
    if remainder != 0
      # Same sign: need to round up (away from zero)
      # Different sign: already rounded towards zero, which is towards +infinity for negative results
      if (self > 0 && other > 0) || (self < 0 && other < 0)
        quotient = quotient + 1
      end
    end

    quotient
  end

  # Return array of digits in given base (least significant first)
  def digits(base = 10)
    result = []
    n = self

    if n == 0
      return [0]
    end

    while n > 0
      result << (n % base)
      n = n / base
    end

    result
  end
end

%s(defun __int (val)
  (add (shl val) 1)
)
