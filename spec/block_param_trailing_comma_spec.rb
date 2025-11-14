require_relative '../rubyspec/spec_helper'

# Block parameter with trailing comma
# See: rubyspec/language/block_spec.rb:88
# Error: "Parse error: Expected: argument"

describe "Block parameter trailing comma" do
  it "accepts trailing comma in block parameter list" do
    result = [1, 2].map { |a, | a }
    result.should == [1, 2]
  end

  it "uses trailing comma to capture only first element" do
    [[1, 2], [3, 4]].map { |a, | a }.should == [1, 3]
  end
end
