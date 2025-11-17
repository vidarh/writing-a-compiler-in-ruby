require_relative '../rubyspec/spec_helper'

describe "%x command execution syntax" do
  it "parses %x(...) syntax without errors" do
    # Note: system() is stubbed to raise an exception since command execution is not implemented
    # This test just verifies the parser handles %x syntax correctly
    lambda { %x(echo hello) }.should raise_error(RuntimeError, /system.*not implemented/)
  end

  it "parses %x{...} syntax without errors" do
    lambda { %x{echo hello} }.should raise_error(RuntimeError, /system.*not implemented/)
  end
end
