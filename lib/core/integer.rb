
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
  # Can accept either an array or a single value
  def __set_heap_data(limbs_or_value, sign)
    # If limbs_or_value is already an array, use it directly
    # Otherwise, wrap single value in array
    if limbs_or_value.is_a?(Array)
      @limbs = limbs_or_value
    else
      @limbs = [limbs_or_value]
    end
    @sign = sign
  end

  # Initialize heap integer from overflow value
  # NOTE: This method is no longer used - now using __set_heap_data instead
  # Array creation happens in __set_heap_data for simplicity
  def __init_overflow(raw_value, sign)
    # Not used - see __add_with_overflow in base.rb
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
    # Reconstruct value from limbs (limited to 32-bit result)
    # WARNING: This only works correctly for values that fit in 32 bits!
    # Multi-limb values > 32-bit will be truncated/incorrect
    # FIXME: Simplified version to avoid self-compilation issues with bit operations
    %s(
      (if (and @limbs (gt (callm @limbs length) 0))
        (let (sign_val raw_sign result limb0 raw_limb0)
          (assign sign_val @sign)
          (assign raw_sign (sar sign_val))

          # Get first limb (bits 0-29) - for now, ignore additional limbs
          (assign limb0 (index @limbs 0))
          (assign raw_limb0 (sar limb0))
          (assign result raw_limb0)

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
    # Dispatch based on whether other is fixnum or heap
    # Check in s-expression and dispatch to appropriate Ruby method
    %s(
      (if (eq (bitand other 1) 1)
        # Other is fixnum
        (return (callm self __add_heap_and_fixnum other))
        # Other is heap
        (return (callm self __add_heap_and_heap other)))
    )
  end

  # Add heap integer to fixnum
  def __add_heap_and_fixnum(fixnum_val)
    my_sign = @sign
    my_limbs = @limbs

    # Extract fixnum value and determine sign, create limb array
    # Do this all in s-expression to avoid assignment issues
    %s(
      (let (raw_val abs_val other_sign_val other_limb)
        (assign raw_val (sar fixnum_val))
        (if (lt raw_val 0)
          (do
            (assign other_sign_val -1)
            (assign abs_val (sub 0 raw_val)))
          (do
            (assign other_sign_val 1)
            (assign abs_val raw_val)))
        (assign other_limb (__int abs_val))
        # Call helper with extracted values
        (return (callm self __add_magnitudes_fixnum (other_limb other_sign_val))))
    )
  end

  # Helper for adding heap integer magnitude with fixnum magnitude
  def __add_magnitudes_fixnum(other_limb, other_sign_val)
    my_sign = @sign
    my_limbs = @limbs
    other_limbs = [other_limb]

    # If signs are different, this becomes subtraction
    if my_sign != other_sign_val
      # Compare magnitudes
      cmp = __compare_magnitudes(my_limbs, other_limbs)

      if cmp == 0
        # Magnitudes equal - result is 0
        return 0
      else
        if cmp > 0
          # |self| > |other| - subtract other from self, keep self's sign
          __subtract_magnitudes(my_limbs, other_limbs, my_sign)
        else
          # |self| < |other| - subtract self from other, use other's sign
          __subtract_magnitudes(other_limbs, my_limbs, other_sign_val)
        end
      end
    else
      # Same sign - add magnitudes
      __add_magnitudes(my_limbs, other_limbs, my_sign)
    end
  end

  # Add two heap integers
  def __add_heap_and_heap(other_heap)
    my_sign = @sign
    my_limbs = @limbs
    other_sign = other_heap.__get_sign
    other_limbs = other_heap.__get_limbs

    # If signs are different, this becomes subtraction
    if my_sign != other_sign
      # Subtract magnitudes: determine which is larger
      cmp = __compare_magnitudes(my_limbs, other_limbs)

      if cmp == 0
        # Magnitudes equal - result is 0
        return 0
      else
        if cmp > 0
          # |self| > |other| - subtract other from self, keep self's sign
          __subtract_magnitudes(my_limbs, other_limbs, my_sign)
        else
          # |self| < |other| - subtract self from other, use other's sign
          __subtract_magnitudes(other_limbs, my_limbs, other_sign)
        end
      end
    else
      # Same sign - add magnitudes
      __add_magnitudes(my_limbs, other_limbs, my_sign)
    end
  end

  # Add two limb arrays (magnitudes only, no sign)
  # Returns new Integer with given sign
  def __add_magnitudes(limbs_a, limbs_b, sign)
    len_a = limbs_a.length
    len_b = limbs_b.length

    # Calculate max using helper
    max_len = __max_fixnum(len_a, len_b)

    result_limbs = []
    carry = 0
    i = 0

    while __less_than(i, max_len) != 0
      # Get limbs from arrays
      limb_a = __get_limb_or_zero(limbs_a, i, len_a)
      limb_b = __get_limb_or_zero(limbs_b, i, len_b)

      # Add limbs with carry
      sum_result = __add_limbs_with_carry(limb_a, limb_b, carry)

      # Check for overflow and subtract limb_base if needed
      # Use s-expression to work with raw limb_base value
      overflow_result = __check_limb_overflow(sum_result)
      adjusted_limb = overflow_result[0]
      new_carry = overflow_result[1]

      result_limbs << adjusted_limb
      carry = new_carry

      i = i + 1
    end

    # If there's still a carry, add a new limb
    if carry != 0
      result_limbs << 1
    end

    # Check if result fits in a fixnum (single limb < 2^30)
    result_len = result_limbs.length
    first_limb = result_limbs[0]
    half_max = __half_limb_base

    should_demote = 0
    if result_len == 1
      if __less_than(first_limb, half_max) != 0
        should_demote = 1
      end
    end

    if should_demote != 0
      # Convert to fixnum
      val = first_limb
      if sign < 0
        val = 0 - val
      end
      return val
    else
      # Create heap integer
      result = Integer.new
      result.__set_heap_data(result_limbs, sign)
      return result
    end
  end

  # Compare two magnitude arrays (ignoring sign)
  # Returns: -1 if a < b, 0 if equal, 1 if a > b
  def __compare_magnitudes(limbs_a, limbs_b)
    len_a = limbs_a.length
    len_b = limbs_b.length

    # Different lengths - longer one is larger
    if len_a != len_b
      if __less_than(len_a, len_b) != 0
        return -1
      else
        return 1
      end
    end

    # Same length - compare from most significant limb
    i = len_a - 1
    while __ge_fixnum(i, 0) != 0
      limb_a = limbs_a[i]
      limb_b = limbs_b[i]

      if limb_a != limb_b
        if __less_than(limb_a, limb_b) != 0
          return -1
        else
          return 1
        end
      end

      i = i - 1
    end

    # All limbs equal
    return 0
  end

  # Subtract limbs_b from limbs_a (assumes limbs_a >= limbs_b)
  # Returns new Integer with given sign
  def __subtract_magnitudes(limbs_a, limbs_b, sign)
    len_a = limbs_a.length
    len_b = limbs_b.length
    max_len = __max_fixnum(len_a, len_b)

    result_limbs = []
    borrow = 0
    i = 0

    while __less_than(i, max_len) != 0
      limb_a = __get_limb_or_zero(limbs_a, i, len_a)
      limb_b = __get_limb_or_zero(limbs_b, i, len_b)

      # Subtract: limb_a - limb_b - borrow
      diff = __subtract_with_borrow(limb_a, limb_b, borrow)

      # Check if we need to borrow and add limb_base if negative
      borrow_result = __check_limb_borrow(diff)
      adjusted_limb = borrow_result[0]
      new_borrow = borrow_result[1]

      result_limbs << adjusted_limb
      borrow = new_borrow

      i = i + 1
    end

    # Remove leading zeros
    result_len = result_limbs.length
    while result_len > 1
      last_limb = result_limbs[result_len - 1]
      if last_limb == 0
        result_len = result_len - 1
      else
        break
      end
    end

    # Trim array if needed
    if result_len != result_limbs.length
      trimmed = []
      j = 0
      while __less_than(j, result_len) != 0
        trimmed << result_limbs[j]
        j = j + 1
      end
      result_limbs = trimmed
    end

    # Check if result fits in a fixnum
    first_limb = result_limbs[0]
    half_max = __half_limb_base

    should_demote = 0
    if result_len == 1
      if __less_than(first_limb, half_max) != 0
        should_demote = 1
      end
    end

    if should_demote != 0
      # Convert to fixnum
      val = first_limb
      if sign < 0
        val = 0 - val
      end
      return val
    else
      # Create heap integer
      result = Integer.new
      result.__set_heap_data(result_limbs, sign)
      return result
    end
  end

  # Subtract limb_b and borrow from limb_a
  # Returns tagged fixnum (may be negative)
  def __subtract_with_borrow(a, b, borrow)
    %s(
      (let (a_raw b_raw borrow_raw diff)
        (assign a_raw (sar a))
        (assign b_raw (sar b))
        (assign borrow_raw (sar borrow))
        (assign diff (sub a_raw b_raw))
        (assign diff (sub diff borrow_raw))
        (return (__int diff)))
    )
  end

  # Add three limbs (a + b + carry) - all are tagged fixnums
  # Returns tagged fixnum result
  def __add_limbs_with_carry(a, b, c)
    %s(
      (let (a_raw b_raw c_raw sum)
        (assign a_raw (sar a))
        (assign b_raw (sar b))
        (assign c_raw (sar c))
        (assign sum (add a_raw b_raw))
        (assign sum (add sum c_raw))
        (return (__int sum)))
    )
  end

  # Helper: max of two fixnums (avoids true/false issues)
  def __max_fixnum(a, b)
    %s((if (gt a b) (return a) (return b)))
  end

  # Helper: a < b for fixnums (avoids true/false issues)
  # Returns 1 if true, 0 if false
  def __less_than(a, b)
    %s((if (lt a b) (return (__int 1)) (return (__int 0))))
  end

  # Helper: a >= b for fixnums (avoids true/false issues)
  # Returns 1 if true, 0 if false
  def __ge_fixnum(a, b)
    %s((if (ge a b) (return (__int 1)) (return (__int 0))))
  end

  # Helper: get limb from array or 0 if out of bounds
  def __get_limb_or_zero(arr, i, len)
    # Use simple Ruby array indexing
    if __less_than(i, len) != 0
      arr[i]
    else
      0
    end
  end

  # Helper: get 2^30 = 1073741824 (limb base) - RETURNS RAW UNTAGGED VALUE
  # Computed in s-expression to avoid bootstrap issues
  # IMPORTANT: This returns an untagged value because 2^30 cannot fit in a fixnum!
  def __limb_base_raw
    %s(
      (let (k1 k2 result)
        (assign k1 1024)
        (assign k2 (mul k1 k1))  # 1024 * 1024 = 1048576
        (assign result (mul k2 k1))  # 1048576 * 1024 = 1073741824
        (return result))  # Return RAW, don't tag with __int!
    )
  end

  # Check if sum overflowed limb boundary and adjust
  # Returns [adjusted_limb, carry] where carry is 0 or 1
  def __check_limb_overflow(sum)
    %s(
      (let (sum_raw limb_base adjusted carry_val)
        (assign sum_raw (sar sum))
        (assign limb_base (callm self __limb_base_raw))

        # Check if sum_raw >= limb_base
        (if (ge sum_raw limb_base)
          (do
            (assign adjusted (sub sum_raw limb_base))
            (assign carry_val 1))
          (do
            (assign adjusted sum_raw)
            (assign carry_val 0)))

        # Return array [adjusted_limb, carry]
        (return (callm self __make_overflow_result ((__int adjusted) (__int carry_val)))))
    )
  end

  # Helper to create [limb, carry] array
  def __make_overflow_result(limb, carry)
    [limb, carry]
  end

  # Check if diff is negative and add limb_base if needed
  # Returns [adjusted_limb, borrow] where borrow is 0 or 1
  def __check_limb_borrow(diff)
    %s(
      (let (diff_raw limb_base adjusted borrow_val)
        (assign diff_raw (sar diff))
        (assign limb_base (callm self __limb_base_raw))

        # Check if diff_raw < 0
        (if (lt diff_raw 0)
          (do
            (assign adjusted (add diff_raw limb_base))
            (assign borrow_val 1))
          (do
            (assign adjusted diff_raw)
            (assign borrow_val 0)))

        # Return array [adjusted_limb, borrow]
        (return (callm self __make_overflow_result ((__int adjusted) (__int borrow_val)))))
    )
  end

  # Helper: get 2^29 = 536870912 (half limb base, max fixnum magnitude)
  def __half_limb_base
    %s(
      (let (k1 k2 result)
        (assign k1 512)
        (assign k2 (mul k1 1024))  # 512 * 1024 = 524288
        (assign result (mul k2 1024))  # 524288 * 1024 = 536870912
        (return (__int result)))
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

  # Compare two integers (heap or fixnum)
  # Returns: -1 if self < other, 0 if equal, 1 if self > other
  # Works on limb arrays for heap integers
  def __cmp(other)
    # Use s-expression to check representations and dispatch
    %s(
      (let (self_is_fixnum other_is_fixnum)
        (assign self_is_fixnum (bitand self 1))
        (assign other_is_fixnum (bitand other 1))

        # If both are fixnums (bit 0 = 1), use simple comparison
        (if (and self_is_fixnum other_is_fixnum)
          (return (callm self __cmp_fixnum_fixnum other)))

        # If self is fixnum but other is heap
        (if self_is_fixnum
          (return (callm self __cmp_fixnum_heap other)))

        # If other is fixnum but self is heap
        (if other_is_fixnum
          (return (callm self __cmp_heap_fixnum other)))

        # Both are heap integers
        (return (callm self __cmp_heap_heap other))
      )
    )
  end

  # Compare two fixnums
  def __cmp_fixnum_fixnum(other)
    %s(
      (let (a b)
        (assign a (sar self))
        (assign b (sar other))
        (if (lt a b) (return (__int -1)))
        (if (gt a b) (return (__int 1)))
        (return (__int 0))
      )
    )
  end

  # Compare fixnum (self) with heap integer (other)
  def __cmp_fixnum_heap(other)
    # Use s-expression for the entire comparison to avoid assignment issues
    %s(
      (let (self_raw other_sign other_raw)
        (assign self_raw (sar self))
        (assign other_sign (sar (callm other __get_sign)))

        # Compare signs: negative < positive
        (if (and (lt self_raw 0) (gt other_sign 0))
          (return (__int -1)))
        (if (and (gt self_raw 0) (lt other_sign 0))
          (return (__int 1)))

        # Same sign - compare magnitudes
        (assign other_raw (callm other __get_raw))
        (if (lt self_raw other_raw)
          (return (__int -1)))
        (if (gt self_raw other_raw)
          (return (__int 1)))
        (return (__int 0))
      )
    )
  end

  # Compare heap integer (self) with fixnum (other)
  def __cmp_heap_fixnum(other)
    # Use s-expression for the entire comparison
    %s(
      (let (other_raw self_sign self_raw)
        (assign other_raw (sar other))
        (assign self_sign (sar (index self 2)))  # @sign is at offset 2

        # Compare signs: negative < positive
        (if (and (lt self_sign 0) (gt other_raw 0))
          (return (__int -1)))
        (if (and (gt self_sign 0) (lt other_raw 0))
          (return (__int 1)))

        # Same sign - compare magnitudes
        (assign self_raw (callm self __get_raw))
        (if (lt self_raw other_raw)
          (return (__int -1)))
        (if (gt self_raw other_raw)
          (return (__int 1)))
        (return (__int 0))
      )
    )
  end

  # Compare two heap integers
  def __cmp_heap_heap(other)
    self_sign = @sign.__get_raw
    other_sign = other.__get_sign.__get_raw

    # Compare signs
    return -1 if self_sign < 0 && other_sign > 0
    return 1 if self_sign > 0 && other_sign < 0

    # Same sign - compare magnitudes (limb by limb)
    self_limbs = @limbs
    other_limbs = other.__get_limbs
    self_len = self_limbs.length
    other_len = other_limbs.length

    # More limbs = larger magnitude
    if self_len < other_len
      return self_sign > 0 ? -1 : 1
    end
    if self_len > other_len
      return self_sign > 0 ? 1 : -1
    end

    # Same number of limbs - compare from most significant to least
    i = self_len - 1
    while i >= 0
      self_limb = self_limbs[i].__get_raw
      other_limb = other_limbs[i].__get_raw

      if self_limb < other_limb
        return self_sign > 0 ? -1 : 1
      end
      if self_limb > other_limb
        return self_sign > 0 ? 1 : -1
      end

      i = i - 1
    end

    # All limbs equal
    0
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


  # Divide limb array by small integer (radix), return quotient limbs and remainder
  # Used for base conversion in to_s
  # Returns [quotient_limbs_array, remainder_value]
  # SIMPLIFIED VERSION: Only handles single-limb heap integers for now
  def __divmod_limbs(limbs, radix)
    # OLD METHOD - kept for compatibility but not used
    # For now, only handle single-limb case
    # Multi-limb division is complex and needs careful implementation
    if limbs.length != 1
      # Multi-limb not yet supported - return placeholder
      return [[0], 0]
    end

    limb_val = limbs[0].__get_raw
    quotient_val = limb_val / radix
    remainder = limb_val % radix

    [[quotient_val], remainder]
  end

  # Divide integer (self) by small fixnum radix
  # Returns [quotient, remainder] where both are fixnums
  # For use in to_s algorithm
  def __divmod_by_fixnum(radix)
    # Dispatch entirely in s-expression
    %s(
      (if (eq (bitand self 1) 1)
        # self is fixnum - simple division
        (let (self_raw radix_raw q r)
          (assign self_raw (sar self))
          (assign radix_raw (sar radix))
          (assign q (div self_raw radix_raw))
          (assign r (mod self_raw radix_raw))
          # Tag and return via Ruby helper
          (return (callm self __make_divmod_array ((__int q) (__int r)))))
        # self is heap integer - call Ruby helper
        (return (callm self __divmod_heap_single_limb radix)))
    )
  end

  # Helper to create divmod result array
  def __make_divmod_array(q, r)
    [q, r]
  end

  # Helper for heap integer division (single or multi-limb)
  def __divmod_heap_single_limb(radix)
    limbs = @limbs
    len = limbs.length

    # Single limb case - use simple division
    if len == 1
      limb0 = limbs[0]
      %s(
        (let (limb sign_raw radix_raw q r)
          # For single-limb heap integers, extract value and divide
          (assign limb (sar limb0))
          (assign sign_raw (sar @sign))
          (assign radix_raw (sar radix))
          (assign q (div limb radix_raw))
          (assign r (mod limb radix_raw))

          # Apply sign
          (if (lt sign_raw 0) (do
            (assign q (sub 0 q))
            (assign r (sub 0 r))))

          # Tag and return via Ruby helper
          (return (callm self __make_divmod_array ((__int q) (__int r)))))
      )
    end

    # Multi-limb case handled in Ruby
    __divmod_heap_multi_limb(radix)
  end

  # Multi-limb division by small radix
  def __divmod_heap_multi_limb(radix)
    limbs = @limbs
    len = limbs.length
    radix_val = radix

    # Process limbs from most significant to least significant
    q_limbs = []
    remainder = 0

    i = len - 1
    while i >= 0
      limb = limbs[i]
      # Compute: value = remainder * 1073741824 + limb, then divide by radix
      # Use s-expression for the arithmetic
      result = __divmod_with_carry(remainder, limb, radix_val)
      q_limb = result[0]
      remainder = result[1]

      q_limbs << q_limb
      i = i - 1
    end

    # Reverse to get least significant first
    q_limbs = q_limbs.reverse

    # Remove leading zeros
    while q_limbs.length > 1 && q_limbs[q_limbs.length - 1] == 0
      q_limbs = q_limbs[0..(q_limbs.length - 2)]
    end

    # Build quotient
    if q_limbs.length == 1 && q_limbs[0] < 536870912
      q = q_limbs[0]
      if @sign < 0
        q = 0 - q
      end
    else
      q = Integer.new
      q.__set_heap_data(q_limbs, @sign)
    end

    r = remainder
    if @sign < 0
      r = 0 - r
    end

    [q, r]
  end

  # Compute (carry * 2^30 + limb) / divisor
  # All inputs are tagged fixnums, carry < 36
  def __divmod_with_carry(carry, limb, divisor)
    # Use s-expression for the arithmetic
    # Since carry < 36 and limb < 2^30, we can use multiplication
    # carry * 1073741824 fits in 36 bits (well within 64-bit range)
    %s(
      (let (carry_raw limb_raw divisor_raw value q r)
        (assign carry_raw (sar carry))
        (assign limb_raw (sar limb))
        (assign divisor_raw (sar divisor))

        # Compute carry_raw * 1073741824 + limb_raw
        # Use multiplication for carry * 2^30
        (assign value (mul carry_raw 1073741824))
        (assign value (add value limb_raw))

        # Divide by divisor
        (assign q (div value divisor_raw))
        (assign r (mod value divisor_raw))

        (return (callm self __make_divmod_array ((__int q) (__int r)))))
    )
  end

  # Convert integer to string with radix support
  # Based on Fixnum#to_s algorithm but works on heap integers
  # Uses __divmod_by_fixnum to avoid __get_raw (which doesn't work for multi-limb)
  def __to_s_multi(radix)
    # Validate radix
    if radix < 2 || radix > 36
      STDERR.puts("ERROR: Invalid radix - must be between 2 and 36")
      return "0"
    end

    # Works for both fixnum and heap integers
    out = ""
    n = self
    neg = self < 0
    if neg
      n = 0 - n
    end

    digits = "0123456789abcdefghijklmnopqrstuvwxyz"

    # Extract digits using repeated division
    while n != 0
      result = n.__divmod_by_fixnum(radix)
      q = result[0]  # quotient
      r = result[1]  # remainder

      # Use remainder directly (it's a tagged fixnum)
      r_val = r
      if r_val < 0
        r_val = 0 - r_val
      end

      out = out + digits[r_val]

      # Break if quotient is less than radix
      if q < radix
        # Add final digit if quotient is non-zero
        if q != 0
          q_val = q
          if q_val < 0
            q_val = 0 - q_val
          end
          out = out + digits[q_val]
        end
        break
      end

      n = q
    end

    if out.empty?
      out = "0"
    elsif neg
      out = out + "-"
    end

    out.reverse
  end

  # Convert to string with optional radix
  def to_s(radix=10)
    __to_s_multi(radix)
  end

  # Inspect - return string representation
  def inspect
    to_s(10)
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
    __cmp(other) > 0
  end

  def >= other
    __cmp(other) >= 0
  end

  def < other
    __cmp(other) < 0
  end

  def <= other
    __cmp(other) <= 0
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

  # Not-equal comparison
  def != other
    !(self == other)
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
