require_relative '../rubyspec/spec_helper'

describe "Integer#size" do
  it "returns 4 for fixnums on 32-bit platform" do
    a = 42
    b = 0
    c = -1
    a.size.should == 4
    b.size.should == 4
    c.size.should == 4
  end

  it "returns 4 bytes minimum for bignums just over fixnum range" do
    # On 32-bit: fixnum range is -2^29 to 2^29-1
    # 2^30 = 1073741824 > fixnum_max, so this is a bignum
    # Needs 4 bytes (minimum size on 32-bit)
    val = 2 ** 30
    val.size.should == 4
  end

  it "returns correct byte count for various bignum sizes" do
    # Test different sizes to ensure formula works correctly
    (256 ** 5).size.should == 6   # 5 bytes of 256 + 1 more
    (256 ** 7).size.should == 8
    (256 ** 8).size.should == 9
    (256 ** 10).size.should == 11
    (256 ** 15).size.should == 16
  end

  it "handles edge cases correctly" do
    # Value one less than next power of 256
    (256 ** 10 - 1).size.should == 10
    (256 ** 8 - 1).size.should == 8
  end
end
