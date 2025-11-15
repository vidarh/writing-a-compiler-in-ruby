require_relative '../rubyspec/spec_helper'

# Block parameter nested destructuring
# See: rubyspec/language/block_spec.rb:679
# Error: "Missing value in expression / op: {|/2 pri=9} / vstack: [] / rightv: [:comma, :a, :b]"
# Pattern: { |(a, b)| } - single arg that gets destructured

describe "Block parameter nested destructuring" do
  it "accepts nested destructuring syntax" do
    result = [[1, 2], [3, 4]].map { |(a, b)| a + b }
    result.should == [3, 7]
  end

  it "works with single nested pair" do
    result = [[1, 2]].map { |(x, y)| x * y }
    result.should == [2]
  end
end
