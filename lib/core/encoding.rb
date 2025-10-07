# Encoding - stub implementation
# The compiler doesn't support proper encoding, so this provides
# minimal stubs to allow specs to compile

class Encoding
  def initialize(name)
    @name = name
  end

  def name
    @name
  end

  def to_s
    @name
  end

  # Stub encoding constants
  US_ASCII = Encoding.new("US-ASCII")
  ASCII_8BIT = Encoding.new("ASCII-8BIT")
  BINARY = ASCII_8BIT  # Alias
  UTF_8 = Encoding.new("UTF-8")
  IBM437 = Encoding.new("IBM437")
  SHIFT_JIS = Encoding.new("Shift_JIS")

  # Class methods
  def self.default_internal
    nil
  end

  def self.default_internal=(encoding)
    # FIXME: Stub - doesn't actually set anything
    nil
  end

  def self.default_external
    US_ASCII
  end

  def self.default_external=(encoding)
    # FIXME: Stub - doesn't actually set anything
    nil
  end
end
