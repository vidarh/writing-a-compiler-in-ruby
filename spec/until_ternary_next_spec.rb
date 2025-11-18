require_relative '../rubyspec/spec_helper'

describe "Until with ternary and next" do
  it "handles ternary operator with next in until modifier" do
    i = 0
    j = 0
    ((i+=1) == 3 ? next : j+=i) until i > 10
    j.should == 63
  end
end
