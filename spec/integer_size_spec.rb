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

  it "returns byte count for small bignums" do
    # 256 = 2^8 (needs 2 bytes: values 0-255 fit in 1 byte, 256 needs 2)
    val = 256
    val.size.should == 2
  end

  it "returns byte count for medium bignums" do
    # 256^2 = 65536 (needs 3 bytes)
    val = 256 * 256
    val.size.should == 3
  end

  it "returns byte count for larger bignums" do
    # 2^30 = 1073741824 (needs 4 bytes)
    val = 2 ** 30
    val.size.should == 4
  end
end
