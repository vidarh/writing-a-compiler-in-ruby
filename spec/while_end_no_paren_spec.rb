require_relative '../rubyspec/spec_helper'

describe "While loop with method chaining WITHOUT parentheses" do
  it "allows method calls on while end without parens" do
    i = 0
    while i < 3
      i = i + 1
    end.should == nil
  end
end
