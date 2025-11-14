require_relative '../rubyspec/spec_helper'

# Block parameter with trailing comma
# See: rubyspec/language/block_spec.rb:88
# Error: "Parse error: Expected: argument"

describe "Block parameter trailing comma" do
  it "accepts trailing comma in block parameter list" do
    result = [1, 2].map { |a, | a }
    result.should == [1, 2]
  end

  it "allows trailing comma without requiring more parameters" do
    result = [1, 2, 3].select { |x, | x > 1 }
    result.should == [2, 3]
  end
end
