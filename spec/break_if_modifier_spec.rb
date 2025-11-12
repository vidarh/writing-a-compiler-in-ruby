require_relative '../rubyspec/spec_helper'

# Documents parser issue with break/next/return combined with if modifier
# Error: break/next/return consume tokens outside their scope when used with if modifier
# See KNOWN_ISSUES.md for details

describe "Control flow with if modifier" do
  it "works with standalone break if" do
    i = 0
    while i < 10
      i = i + 1
      break if i == 5
    end
    i.should == 5
  end

  it "handles break if in assignment" do
    i = 0
    result = nil
    while i < 10
      i = i + 1
      result = break if i == 5
      result = i
    end
    result.should == 4
  end

  it "handles break if in parentheses" do
    i = 0
    while i < 10
      i = i + 1
      (break if i == 5)
    end
    i.should == 5
  end

  it "handles break if with or-assign" do
    a = nil
    i = 0
    while i < 10
      i = i + 1
      a ||= break if i == 5
      a = i
    end
    a.should == 4
  end
end
