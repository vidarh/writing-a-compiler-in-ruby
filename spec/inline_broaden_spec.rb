require_relative '../rubyspec/spec_helper'

# Regression tests for the broadened devirt-driven inliner (INLINE=1).
# These tests are valid Ruby; they pass with or without inlining enabled.

# NOTE: InlineBox is defined BEFORE the describe block. Defining a class after its
# first use triggers a pre-existing compiler segfault (forward-reference class bug).
class InlineBox
  def initialize(v)
    @v = v
  end

  def value
    return @v
  end

  def doubled_value
    @tmp = @v
    return @v + @v
  end

  def set(v)
    @v = v
  end

  def set_double(v)
    @v = v + v
  end

  def set_or_clear(flag, v)
    @v = flag ? v : 0
  end
end

describe "Broadened devirt inlining" do
  before do
    @box = InlineBox.new(7)
  end

  it "inlines a getter with an explicit return" do
    @box.value.should == 7
  end

  it "inlines a multi-statement method whose final statement is a return" do
    @box.doubled_value.should == 14
  end

  it "inlines a setter with a side-effect-free arithmetic argument" do
    @box.set(10 + 5)
    @box.value.should == 15
  end

  it "safely duplicates a side-effect-free argument used multiple times in the body" do
    @box.set_double(3)
    @box.value.should == 6
  end

  it "inlines a method whose argument is a conditional side-effect-free expression" do
    @box.set_or_clear(true, 99)
    @box.value.should == 99

    @box.set_or_clear(false, 99)
    @box.value.should == 0
  end
end
