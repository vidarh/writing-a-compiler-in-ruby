require_relative '../rubyspec/spec_helper'

# Category 3: Ternary expression evaluation
# Tests whether ternary expressions evaluate correctly in cases the
# compiler historically got wrong.
#
# Related @bug markers:
#   treeoutput.rb:235 - ternary || evaluates to false in compiler
#   treeoutput.rb:262 - ternary causes selftest-c failure

describe "ternary expression evaluation" do
  it "ternary with || in condition where first is truthy" do
    comma = true
    block = false
    result = comma || block ? "yes" : "no"
    result.should == "yes"
  end

  it "ternary with || where first operand is falsy but second is truthy" do
    a = false
    b = true
    result = a || b ? "yes" : "no"
    result.should == "yes"
  end

  it "ternary with || where both are falsy" do
    result = nil || false ? "yes" : "no"
    result.should == "no"
  end

  it "ternary assigned to variable used in subsequent method call" do
    lv = [1, 2]
    rightv = [3, 4]
    args = lv ? lv + rightv : rightv
    args.should == [1, 2, 3, 4]
  end

  it "ternary assigned to variable where condition is nil (else branch)" do
    lv = nil
    rightv = [3, 4]
    args = lv ? lv + rightv : rightv
    args.should == [3, 4]
  end

  it "ternary with array wrapping condition" do
    lv = 42
    result = (lv && !lv.is_a?(Array)) ? [lv] : lv
    result.should == [42]
  end

  it "nested ternary expression" do
    a = true
    b = true
    result = a ? (b ? "both" : "only_a") : "none"
    result.should == "both"
  end
end
