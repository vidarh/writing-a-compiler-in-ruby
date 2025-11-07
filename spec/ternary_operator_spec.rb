require_relative '../rubyspec/spec_helper'

describe "The ternary operator" do
  it "returns the true branch when condition is literal true" do
    result = true ? "correct" : "wrong"
    result.should == "correct"
  end

  it "returns the false branch when condition is literal false" do
    result = false ? "wrong" : "correct"
    result.should == "correct"
  end

  it "returns the true branch when condition variable is true" do
    condition = true
    result = condition ? "correct" : "wrong"
    result.should == "correct"
  end

  it "returns the false branch when condition variable is false" do
    condition = false
    result = condition ? "wrong" : "correct"
    result.should == "correct"
  end

  it "works with variable values in branches" do
    condition = false
    scope = "SCOPE_VALUE"
    result = condition ? "WRONG" : scope
    result.should == "SCOPE_VALUE"
  end
end
