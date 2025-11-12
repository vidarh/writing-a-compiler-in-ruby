require_relative '../rubyspec/spec_helper'

# Documents parser error with ||= and parenthesized multi-line expression
# Error: "Missing value in expression / op: {or_assign/2 pri=7}"
# See KNOWN_ISSUES.md for details

describe "Or-assign with parenthesized expression" do
  it "handles ||= with simple parenthesized expression" do
    a = [nil, nil]
    a[1] ||= (42)
    a[1].should == 42
  end

  it "handles ||= with multi-line parenthesized expression" do
    a = [nil, nil]
    a[1] ||= (
      x = 42
      x
    )
    a[1].should == 42
  end

  it "handles ||= with parenthesized expression containing break" do
    a = [nil, nil]
    c = true
    while c
      a[1] ||= (
        break if c
        c = false
      )
    end
    a[1].should == nil
  end
end
