# Minimal Integer class for early bootstrap
# This version only supports tagged fixnums (no bignums/heap integers)
# Does NOT depend on Array
# Full Integer with bignum support loaded later in integer.rb

class Integer < Numeric
  # Minimal constants
  MAX = 536870911   # 2^29 - 1
  MIN = -536870912  # -2^29

  def class
    Integer
  end

  def hash
    # For fixnums, just return self
    self
  end

  def % other
    %s(assign r (sar other))
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

  def > other
    %s(if (gt (sar self) (sar other)) true false)
  end

  def >= other
    %s(if (ge (sar self) (sar other)) true false)
  end

  def < other
    %s(if (lt (sar self) (sar other)) true false)
  end

  def <= other
    %s(if (le (sar self) (sar other)) true false)
  end

  def == other
    # Handle nil
    if other.nil?
      return false
    end
    # For fixnums, direct comparison
    %s(if (eq self other) true false)
  end
end

# __int function - converts raw value to tagged fixnum
%s(defun __int (val)
  (add (shl val) 1)
)
