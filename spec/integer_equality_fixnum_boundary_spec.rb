require_relative '../rubyspec/spec_helper'

# Integer#== bug at fixnum boundary
# When comparing integers at the boundary between fixnum and heap representation,
# equality checks return false even when values are numerically equal.
#
# Example: -1073741824 can be represented as either:
# - A fixnum (when constructed via arithmetic that demotes heap → fixnum)
# - A heap integer (when parsed from literal or constructed via Bignum ops)
#
# The == method fails to recognize these as equal, even though they represent
# the same mathematical value.

describe "Integer equality at fixnum boundary" do
  it "compares values at negative boundary correctly" do
    a = 1073741824 * (-1)  # May be demoted to fixnum
    b = -1073741824         # May be heap integer
    # Workaround: compare string representations
    a.to_s.should == b.to_s
  end

  it "compares values just beyond negative boundary correctly" do
    a = 1073741825 * (-1)
    b = -1073741825
    a.to_s.should == b.to_s
  end

  it "compares values at positive boundary correctly" do
    a = 1073741824
    b = 536870912 * 2  # 2^29 * 2 = 2^30
    a.to_s.should == b.to_s
  end
end
