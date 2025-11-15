require_relative '../rubyspec_helper'

# Method chaining on for...end loops
# See: rubyspec/language/for_spec.rb:261
# Error: "Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :should"

describe "for...end with method chaining" do
  it "returns the iterable and allows method chaining" do
    result = for i in 1..3; end
    result.should == (1..3)
  end

  it "allows chaining .class after for...end" do
    (for i in 1..3; end).class.should == Range
  end

  it "allows chaining arbitrary methods" do
    (for i in [:a, :b]; end).length.should == 2
  end
end
