
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
  def __init_overflow(raw_value, sign)
    # For now, store the full value in a single limb
    # TODO: Properly split into 30-bit limbs
    @limbs = [raw_value]
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
    # For single-limb heap integers, extract the value
    # Always use s-expression to ensure proper raw value handling
    %s(
      (if (and @limbs (gt (callm @limbs length) 0))
        (let (limb_val sign_val raw_limb raw_sign result)
          (assign limb_val (index @limbs 0))
          (assign sign_val @sign)
          (assign raw_limb (sar limb_val))
          (assign raw_sign (sar sign_val))
          (if (lt raw_sign 0)
            (assign result (sub 0 raw_limb))
            (assign result raw_limb))
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

  # Add tagged fixnum to heap integer
  # Called when self is tagged fixnum and other is heap integer
  def __add_fixnum_to_heap(heap_int)
    # TODO: Implement fixnum + heap integer
    %s(dprintf 2 "fixnum + heap integer\n")
    0
  end

  # Add heap integer to another value
  # Called when self is a heap-allocated integer
  def __add_heap(other)
    %s(dprintf 2 "__add_heap called (self=heap, other=0x%lx)\n" other)

    # For now, simple implementation: extract our limb value, add to other
    # This is incomplete but allows basic testing
    if @limbs && @limbs.length > 0
      my_value_tagged = @limbs[0]

      # Check if other is tagged fixnum or heap integer
      %s(
        (if (eq (bitand other 1) 1)
          # other is tagged fixnum - extract its value
          (let (my_val other_val result)
            # Extract raw value from our tagged limb
            (assign my_val (sar my_value_tagged))
            # Extract raw value from other tagged integer
            (assign other_val (sar other))
            # Add them
            (assign result (add my_val other_val))
            # Return as tagged fixnum (TODO: check for overflow)
            (return (__int result)))
          # other is also heap integer - not yet implemented
          (do
            (dprintf 2 "ERROR: heap + heap not yet implemented\n")
            (return 0)))
      )
    else
      0
    end
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
