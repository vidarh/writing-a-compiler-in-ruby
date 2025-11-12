require_relative '../rubyspec/spec_helper'

describe "While loop with method chaining on end" do
  it "allows method calls on while end" do
    i = 0
    (while i < 3
      i = i + 1
    end).should == nil
  end

  it "allows method calls on until end" do
    i = 0
    (until i > 2
      i = i + 1
    end).should == nil
  end
end
