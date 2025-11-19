# Encoding - stub implementation
# The compiler doesn't support proper encoding, so this provides
# minimal stubs to allow specs to compile

class Encoding
  class CompatibilityError < StandardError
  end

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
  CESU_8  = Encoding.new("CESU_8")
  EUC_JP  = Encoding.new("EUC_JP")
  Big5 = Encoding.new("Big5")
  ISO_8859_1 = Encoding.new("ISO-8859-1")
  ISO_8859_16 = Encoding.new("ISO-8859-16")
  Windows_31J = Encoding.new("Windows-31J")

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

  def self.find(name)
    # FIXME: Stub - just return UTF_8 for everything
    # In a real implementation, this would look up the encoding by name
    case name
    when "UTF-8", "utf-8", "Utf-8"
      UTF_8
    when "US-ASCII", "us-ascii"
      US_ASCII
    when "ASCII-8BIT", "BINARY", "binary"
      BINARY
    when "Shift_JIS", "shift_jis"
      SHIFT_JIS
    when "EUC-JP", "euc-jp"
      EUC_JP
    when "CESU-8", "cesu-8"
      CESU_8
    when "ISO-8859-9", "iso-8859-9"
      Encoding.new("ISO-8859-9")
    when "TIS-620", "tis-620"
      Encoding.new("TIS-620")
    else
      Encoding.new(name)
    end
  end
end

# __ENCODING__ pseudo-variable
# Returns the encoding of the current source file
# FIXME: This is a stub that always returns US_ASCII
# In a real implementation, this would track the actual source file encoding
def __ENCODING__
  Encoding::US_ASCII
end
