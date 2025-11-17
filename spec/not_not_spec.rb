require_relative '../rubyspec/spec_helper'

describe "not operator" do
  it "works with double not" do
    result = not not false
    result.should == false
  end

  it "works with double not on truthy value" do
    result = not not 10
    result.should == true
  end
end
