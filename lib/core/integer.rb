
class Integer < Numeric
  # Integer supports two representations:
  # 1. Tagged fixnum: value stored as (n << 1) | 1, low bit = 1
  #    Range: -536,870,912 to 536,870,911 (30-bit signed)
  # 2. Heap integer: object with @limbs (Array) and @sign (1 or -1)
  #    Used when value overflows fixnum range
  #
  # Methods must check representation:
  # - Tagged fixnums use bitwise ops in %s() expressions
  # - Heap integers use @limbs/@sign instance variables

  # Stub constants - proper limits not implemented
  # Using 29-bit signed integer limits (due to tagging)
  MAX = 268435455   # 2^28 - 1
  MIN = -268435456  # -2^28

  # Initialize a heap-allocated integer
  # This is NOT called for tagged fixnums (immediate values)
  # Only called when Integer.new is explicitly called (for heap integers)
  def initialize
    @limbs = []
    @sign = 1
  end

  # Helper to set instance variables from s-expression context
  # Used when allocating heap integers from low-level code
  def __set_heap_data(limbs, sign)
    @limbs = limbs
    @sign = sign
  end

  # Initialize heap integer from overflow value
  # Called from __add_with_overflow when allocation is needed
  # Splits the raw value into 30-bit limbs (unsigned magnitude)
  def __init_overflow(raw_value, sign)
    # Get absolute value to split into limbs
    abs_val = raw_value
    if abs_val < 0
      abs_val = -abs_val
    end

    # Split into 30-bit limbs
    # Each limb holds bits [i*30 .. (i+1)*30-1]
    limbs = []
    if abs_val == 0
      limbs = [0]
    else
      # Extract 30-bit chunks
      limb_mask = (1 << 30) - 1  # 0x3FFFFFFF = 30 bits of 1s
      while abs_val > 0
        limb_val = abs_val & limb_mask
        limbs << limb_val
        abs_val = abs_val >> 30
      end
    end

    @limbs = limbs
    @sign = sign
  end

  # Get raw integer value
  # For tagged fixnums: extract by right shift
  # For heap integers: extract from limbs (single-limb only for now)
  def __get_raw
    %s(
      (if (eq (bitand self 1) 1)
        # Tagged fixnum - extract raw value
        (return (sar self))
        # Heap integer - extract from @limbs
        (return (callm self __heap_get_raw)))
    )
  end

  def __heap_get_raw
    # Reconstruct value from limbs (limited to 32-bit result)
    # WARNING: This only works correctly for values that fit in 32 bits!
    # Multi-limb values > 32-bit will be truncated/incorrect
    %s(
      (if (and @limbs (gt (callm @limbs length) 0))
        (let (limb_count sign_val raw_sign result limb0 raw_limb0 limb1 raw_limb1)
          (assign limb_count (callm @limbs length))
          (assign sign_val @sign)
          (assign raw_sign (sar sign_val))

          # Get first limb (bits 0-29)
          (assign limb0 (index @limbs 0))
          (assign raw_limb0 (sar limb0))
          (assign result raw_limb0)

          # If there's a second limb, add bits 30-59
          (if (gt limb_count 1)
            (do
              (assign limb1 (index @limbs 1))
              (assign raw_limb1 (sar limb1))
              # Shift limb1 left by 30 bits and add to result
              (assign raw_limb1 (sall 30 raw_limb1))
              (assign result (add result raw_limb1))))

          # Apply sign
          (if (lt raw_sign 0)
            (assign result (sub 0 result)))
          (return result))
        (return 0))
    )
  end

  # Addition - handles both tagged fixnums and heap integers
  def + other
    # Check bit 0 of self: if 1, it's a tagged fixnum; if 0, it's a heap object
    # Do this check entirely in s-expression to avoid bitand issues in Ruby code
    %s(
      (if (eq (bitand self 1) 1)
        # Tagged fixnum path
        (do
          # Check if other is also a tagged fixnum
          (if (eq (bitand other 1) 1)
            # Both tagged fixnums - use existing arithmetic with overflow detection
            (let (a b)
              (assign a (sar self))
              (assign b (sar other))
              (return (__add_with_overflow a b)))
            # self is tagged fixnum, other is heap integer - dispatch to Ruby
            (return (callm self __add_fixnum_to_heap other))))
        # Heap integer - dispatch to Ruby implementation
        (return (callm self __add_heap other)))
    )
  end

  # Subtraction - handles both tagged fixnums and heap integers
  def - other
    %s(
      (if (eq (bitand self 1) 1)
        # Tagged fixnum path
        (do
          # Check if other is also a tagged fixnum
          (if (eq (bitand other 1) 1)
            # Both tagged fixnums - subtraction with overflow detection
            (let (a b result)
              (assign a (sar self))
              (assign b (sar other))
              (assign result (sub a b))
              # Use __add_with_overflow to handle overflow
              (return (__add_with_overflow result 0)))
            # self is fixnum, other is heap - delegate to __get_raw for now
            (let (a b result)
              (assign a (sar self))
              (assign b (callm other __get_raw))
              (assign result (sub a b))
              (return (__add_with_overflow result 0)))))
        # Heap integer - delegate to __get_raw for now
        (let (a b result)
          (assign a (callm self __get_raw))
          (assign b (callm other __get_raw))
          (assign result (sub a b))
          (return (__add_with_overflow result 0))))
    )
  end

  # Add tagged fixnum to heap integer
  # Called when self is tagged fixnum and other is heap integer
  def __add_fixnum_to_heap(heap_int)
    # Extract values and use __add_with_overflow
    %s(
      (let (my_val other_val)
        (assign my_val (sar self))
        (assign other_val (callm heap_int __get_raw))
        (return (__add_with_overflow my_val other_val)))
    )
  end

  # Add heap integer to another value
  # Called when self is a heap-allocated integer
  def __add_heap(other)
    # For now, use __get_raw for both operands
    # TODO: Use multi-limb addition
    %s(
      (let (a b)
        (assign a (callm self __get_raw))
        (assign b (callm other __get_raw))
        (return (__add_with_overflow a b)))
    )
  end

  # Helper to get sign for multi-limb operations
  def __get_sign
    @sign
  end

  # Helper to get limbs for multi-limb operations
  def __get_limbs
    @limbs
  end

  # Multi-limb addition: add two heap integers
  # This is the core bignum addition algorithm with carry propagation
  def __add_multi_limb(other)
    my_sign = @sign
    other_sign = other.__get_sign
    my_sign_raw = my_sign.__get_raw
    other_sign_raw = other_sign.__get_raw

    # If signs differ, this is actually subtraction
    if my_sign_raw != other_sign_raw
      # TODO: Implement subtraction
      # For now, fall back to __get_raw (breaks for large numbers)
      %s(
        (let (a b)
          (assign a (callm self __get_raw))
          (assign b (callm other __get_raw))
          (return (__add_with_overflow a b)))
      )
      return  # unreachable
    end

    # Same sign: add magnitudes
    my_limbs = @limbs
    other_limbs = other.__get_limbs
    my_len = my_limbs.length
    other_len = other_limbs.length
    max_len = my_len
    if other_len > my_len
      max_len = other_len
    end

    result_limbs = []
    carry = 0
    i = 0

    # Add limb by limb with carry
    limb_mask = (1 << 30) - 1  # 30-bit mask (0x3FFFFFFF)
    while i < max_len
      my_limb_val = 0
      if i < my_len
        my_limb_val = my_limbs[i].__get_raw
      end

      other_limb_val = 0
      if i < other_len
        other_limb_val = other_limbs[i].__get_raw
      end

      sum = my_limb_val + other_limb_val + carry
      result_limbs << (sum & limb_mask)
      carry = sum >> 30  # Carry is the overflow past 30 bits

      i = i + 1
    end

    # If there's still carry, add another limb
    if carry > 0
      result_limbs << carry
    end

    # Create result heap integer
    result = Integer.new
    result.__set_heap_data(result_limbs, @sign)
    result
  end


  # Inspect - return string representation
  def inspect
    # For heap integers, extract raw value and convert to string
    # For fixnums, delegate to Fixnum#inspect
    %s(
      (if (eq (bitand self 1) 1)
        # Tagged fixnum - will use Fixnum#inspect
        (return 0)
        # Heap integer - convert raw value to string
        (let (raw_val)
          (assign raw_val (callm self __get_raw))
          (assign raw_val (__int raw_val))
          (return (callm raw_val to_s 10))))
    )
    # Fallback (never reached)
    "0"
  end

  # Arithmetic operators - temporary delegation to __get_raw
  # TODO: Implement proper heap integer arithmetic
  def % other
    %s(
      (let (a b result)
        (assign a (callm self __get_raw))
        (assign b (callm other __get_raw))
        (assign result (mod a b))
        (return (__int result)))
    )
  end

  def * other
    %s(
      (let (a b result)
        (assign a (callm self __get_raw))
        (assign b (callm other __get_raw))
        (assign result (mul a b))
        (return (__add_with_overflow result 0)))
    )
  end

  def / other
    %s(
      (let (a b result)
        (assign a (callm self __get_raw))
        (assign b (callm other __get_raw))
        (assign result (div a b))
        (return (__int result)))
    )
  end

  # Unary minus
  def -@
    %s(
      (let (raw)
        (assign raw (callm self __get_raw))
        (assign raw (sub 0 raw))
        (return (__add_with_overflow raw 0)))
    )
  end

  # Spaceship operator for comparison (returns -1, 0, or 1)
  def <=> other
    %s(
      (let (a b)
        (assign a (callm self __get_raw))
        (assign b (callm other __get_raw))
        (if (lt a b)
          (return (__int -1))
          (if (gt a b)
            (return (__int 1))
            (return (__int 0)))))
    )
  end

  # Absolute value
  def abs
    %s(
      (let (raw)
        (assign raw (callm self __get_raw))
        (if (lt raw 0)
          (assign raw (sub 0 raw)))
        (return (__add_with_overflow raw 0)))
    )
  end

  # Bitwise operators - delegate to __get_raw
  def & other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitand (callm self __get_raw) other_raw))
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      nil
    end
  end

  def | other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitor (callm self __get_raw) other_raw))
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      nil
    end
  end

  def ^ other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitxor (callm self __get_raw) other_raw))
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      nil
    end
  end

  def ~
    -(self + 1)
  end

  def << other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (bitand (sall other_raw (callm self __get_raw)) 0x7fffffff))
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      nil
    end
  end

  def >> other
    if other.is_a?(Integer)
      other_raw = other.__get_raw
      %s(__int (sarl other_raw (callm self __get_raw)))
    else
      STDERR.puts("TypeError: Integer can't be coerced into Integer")
      nil
    end
  end

  # Predicates
  def zero?
    %s(if (eq (callm self __get_raw) 0) true false)
  end

  def even?
    self % 2 == 0
  end

  def odd?
    (self % 2) != 0
  end

  # Utility methods
  def to_i
    self
  end

  def succ
    self + 1
  end

  def next
    self + 1
  end

  def pred
    self - 1
  end

  # Comparison operators - for now, just delegate to __get_raw
  # This is a temporary workaround until proper heap integer comparisons are implemented
  def > other
    %s(if (gt (callm self __get_raw) (callm other __get_raw)) true false)
  end

  def >= other
    %s(if (ge (callm self __get_raw) (callm other __get_raw)) true false)
  end

  def < other
    %s(if (lt (callm self __get_raw) (callm other __get_raw)) true false)
  end

  def <= other
    %s(if (le (callm self __get_raw) (callm other __get_raw)) true false)
  end

  # Equality comparison - handles both tagged fixnums and heap integers
  def == other
    # Handle nil and non-Numeric types
    if other.nil?
      return false
    end
    return false if !other.is_a?(Numeric)

    # Compare raw values using __get_raw for both sides
    %s(if (eq (callm self __get_raw) (callm other __get_raw)) true false)
  end

  def numerator
    self
  end

  def denominator
    1
  end

  def to_r
    Rational.new(self,1)
  end

  # Unary plus - returns self
  def +@
    self
  end

  # Integer square root using Newton's method
  def self.sqrt(n)
    n = Integer(n)

    return 0 if n == 0
    return 1 if n < 4

    # Newton's method for integer square root
    # Start with a reasonable initial guess
    x = n / 2
    while true
      x1 = (x + n / x) / 2
      # Break when we've converged (x1 >= x means we're done improving)
      if x1 >= x
        return x
      end
      x = x1
    end
  end

  # FIXME: Stub - should try to convert to Integer
  def self.try_convert(obj)
    return obj if obj.is_a?(Integer)
    if obj.respond_to?(:to_int)
      obj.to_int
    else
      nil
    end
  end

  # Check if this integer is a heap-allocated bignum (vs tagged fixnum)
  # Tagged fixnums have low bit = 1 (odd addresses)
  # Heap objects have low bit = 0 (even addresses)
  # NOTE: This implementation may have issues during self-compilation
  # For now, always return false until we actually create heap integers
  def __is_heap_integer?
    # FIXME: bitand check causes segfault in selftest-c
    # %s(if (eq (bitand self 1) 0) true false)
    # Temporary: always return false
    false
  end

end

# Global Integer() conversion method
def Integer(value)
  return value if value.is_a?(Integer)
  return value.to_i if value.is_a?(Float)
  # FIXME: Should call to_int if available, then to_i, then raise TypeError
  value.to_i
end
