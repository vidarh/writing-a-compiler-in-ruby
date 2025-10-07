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
    %s(__int (add (sar self) (callm other __get_raw)))
  end

  def - other
    %s(__int (sub (sar self) (callm other __get_raw)))
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

  # FIXME: Stub - actual bitwise AND implementation needed
  def & other
    0
  end

  # FIXME: Stub - actual bitwise OR implementation needed
  def | other
    self
  end

  # FIXME: Stub - actual bitwise XOR implementation needed
  def ^ other
    0
  end

  # Bitwise NOT: flips all bits
  # For two's complement: ~n = -n-1
  def ~
    -(self + 1)
  end

  # FIXME: Stub - actual left shift implementation needed
  def << other
    self
  end

  # FIXME: Stub - actual right shift implementation needed
  def >> other
    o = other.to_i + 1
    %s(assign o (sar o)) # Strip type tag
    %s(__int
        (sarl o self)
    )
  end

  # Unary minus
  def -@
    %s(__int (sub 0 (sar self)))
  end

  def ord
    self
  end
  
  def times
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

  # FIXME: Stub - for integers, truncate just returns self
  def truncate(ndigits=0)
    self
  end

  # FIXME: Stub - actual GCD implementation needed
  def gcd(other)
    1
  end

  # FIXME: Stub - actual LCM implementation needed
  def lcm(other)
    self * other
  end

  # FIXME: Stub - actual gcdlcm implementation needed
  def gcdlcm(other)
    [gcd(other), lcm(other)]
  end

  # FIXME: Stub - actual ceildiv implementation needed
  def ceildiv(other)
    self / other
  end

  # FIXME: Stub - actual digits implementation needed
  def digits(base = 10)
    # Should return array of digits in given base
    # For now return empty array
    []
  end
end

%s(defun __int (val)
  (add (shl val) 1)
)
