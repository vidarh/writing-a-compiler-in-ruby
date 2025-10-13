
class Float
  # Stub constants - proper IEEE 754 values not implemented
  # IMPORTANT: Cannot use large literals during compilation - they cause overflow
  # Use computed values instead
  INFINITY = 1 << 28  # Large value without literal overflow
  MAX = (1 << 28) - 1

  # Reserve space for double value (8 bytes = 2 slots)
  # We use instance variables to ensure the compiler allocates space
  def initialize
    @value_low = 0
    @value_high = 0
  end

  def to_s
    # FIXME: Stub - proper float to string not implemented
    "0.0"
  end

  def inspect
    to_s
  end

  def to_i
    # FIXME: Stub - proper float to int conversion not implemented
    0
  end

  def to_int
    to_i
  end

  def to_f
    self
  end

  def class
    Float
  end

  # FIXME: Minimal stubs - operations not fully implemented
  def + other
    self
  end

  def - other
    self
  end

  def * other
    self
  end

  def / other
    self
  end

  def == other
    false
  end

  def < other
    false
  end

  def > other
    false
  end

  def <= other
    false
  end

  def >= other
    false
  end

  # FIXME: Stub for internal coercion - needed by comparison operators
  def __get_raw
    0
  end
end
