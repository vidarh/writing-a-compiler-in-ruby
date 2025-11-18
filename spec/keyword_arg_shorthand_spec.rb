require_relative '../rubyspec/spec_helper'

describe "Keyword argument shorthand" do
  it "expands {a:} to {a: a} in hash literals" do
    a = 42
    h = {a: a}
    h[:a].should == 42
  end

  it "expands {a:, b:} to {a: a, b: b}" do
    a = 1
    b = 2
    h = {a: a, b: b}
    h[:a].should == 1
    h[:b].should == 2
  end
end
