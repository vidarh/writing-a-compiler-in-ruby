require_relative '../rubyspec/spec_helper'

describe "Array indexing with splat and begin block" do
  it "supports splat operator with begin block in array indexing" do
    h = {k: 10}
    (h[*begin [:k] end] += 10).should == 20
    h[:k].should == 20
  end
end
