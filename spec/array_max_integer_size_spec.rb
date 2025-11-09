require_relative '../rubyspec/spec_helper'

# This spec documents a failed attempt to implement Integer#size
# using [4, (bit_length*7)/8].max
# This approach failed during implementation

describe "Array#max with Integer#size calculation" do
  it "should work with array literal and max" do
    val = 256 ** 7
    bit_len = val.bit_length

    # The failed attempt used: [4, (bit_length*7)/8].max
    # This should return the maximum of 4 and the calculated value
    result = [4, (bit_len + 7) / 8].max
    result.should == 8
  end

  it "should work with simple array max" do
    result = [4, 8].max
    result.should == 8
  end

  it "should work with max when first element is larger" do
    result = [10, 3].max
    result.should == 10
  end
end
