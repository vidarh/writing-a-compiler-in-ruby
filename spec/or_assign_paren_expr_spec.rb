require_relative '../rubyspec/spec_helper'

# Documents parser error with ||= and parenthesized multi-line expression
# Error: "Missing value in expression / op: {or_assign/2 pri=7}"
# See KNOWN_ISSUES.md for details

describe "Or-assign with parenthesized expression" do
  it "handles ||= with simple parenthesized expression" do
    a = nil
    a ||= (42)
    a.should == 42
  end

  it "handles ||= with multi-line parenthesized expression" do
    a = nil
    a ||= (
      x = 42
      x
    )
    a.should == 42
  end

  it "handles ||= with parenthesized expression containing break" do
    a = nil
    c = true
    while c
      a ||= (
        break
      )
    end
    a.should == nil
  end
end
