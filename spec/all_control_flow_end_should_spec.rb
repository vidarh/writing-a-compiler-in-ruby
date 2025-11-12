require_relative '../rubyspec/spec_helper'

# Systematically test end.should without parens for all control flow keywords
describe "Control flow end.should without parentheses" do
  it "works with if end.should" do
    if true
      42
    end.should == 42
  end

  it "works with unless end.should" do
    unless false
      42
    end.should == 42
  end

  it "works with while end.should" do
    i = 0
    while i < 3
      i = i + 1
    end.should == nil
  end

  it "works with until end.should" do
    i = 0
    until i > 9
      i = i + 1
    end.should == nil
  end
end
