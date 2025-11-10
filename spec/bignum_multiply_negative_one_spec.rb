require_relative '../rubyspec/spec_helper'

# See KNOWN_ISSUES.md #?? - Bignum multiplication by -1 produces corrupted values
# Root cause: Bug in __multiply_heap_by_fixnum when fixnum is negative
#
# When a heap integer (Bignum) at the fixnum boundary (1073741824 = 2^30)
# is multiplied by -1, the result is corrupted to 9903520314283042198119251968
# instead of the correct -1073741824.
#
# This affects tokenization of negative integer literals at the boundary,
# causing selftest failure in "Parse large negative integer" test.

describe "Bignum multiplication by negative fixnum" do
  it "correctly multiplies heap integer by -1" do
    # 1073741824 = 2^30, just beyond fixnum boundary (max_fixnum = 2^30 - 1)
    a = 1073741824
    result = a * (-1)
    # Use string comparison to workaround Integer#== bug with mixed representations
    result.to_s.should == "-1073741824"
  end

  it "correctly multiplies heap integer by positive 1" do
    a = 1073741824
    result = a * 1
    result.to_s.should == "1073741824"
  end

  it "correctly multiplies slightly larger heap integer by -1" do
    a = 1073741825
    result = a * (-1)
    result.to_s.should == "-1073741825"
  end

  it "correctly multiplies heap integer by -2" do
    a = 1073741824
    result = a * (-2)
    result.to_s.should == "-2147483648"
  end
end
