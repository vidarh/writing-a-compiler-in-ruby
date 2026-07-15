require_relative '../rubyspec/spec_helper'

# Regression tests for the broadened devirt-driven inliner (INLINE=1).
# These tests are valid Ruby; they pass with or without inlining enabled.
#
# The actual calls are placed inside regular instance methods (InlineHarness) rather
# than directly in mspec `it` blocks, because `it` bodies are installed as singleton
# methods and calls inside singleton methods are not devirtualizable.

# NOTE: InlineBox/InlineHarness are defined BEFORE the describe block. Defining a
# class after its first use triggers a pre-existing compiler segfault.
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

  def set_with_default(v, d = 0)
    @v = v + d
  end
end

class InlineHarness
  def getter_with_return
    box = InlineBox.new(7)
    box.value
  end

  def multi_statement_return
    box = InlineBox.new(7)
    box.doubled_value
  end

  def setter_with_expression_arg
    box = InlineBox.new(0)
    box.set(10 + 5)
    box.value
  end

  def duplicated_expression_arg
    box = InlineBox.new(0)
    box.set_double(3)
    box.value
  end

  def conditional_expression_arg
    box = InlineBox.new(0)
    box.set_or_clear(true, 99)
    v1 = box.value
    box.set_or_clear(false, 99)
    v2 = box.value
    [v1, v2]
  end

  def optional_arg_provided
    box = InlineBox.new(0)
    box.set_with_default(5, 3)
    box.value
  end
end

describe "Broadened devirt inlining" do
  before do
    @h = InlineHarness.new
  end

  it "inlines a getter with an explicit return" do
    @h.getter_with_return.should == 7
  end

  it "inlines a multi-statement method whose final statement is a return" do
    @h.multi_statement_return.should == 14
  end

  it "inlines a setter with a side-effect-free arithmetic argument" do
    @h.setter_with_expression_arg.should == 15
  end

  it "safely duplicates a side-effect-free argument used multiple times in the body" do
    @h.duplicated_expression_arg.should == 6
  end

  it "inlines a method whose argument is a conditional side-effect-free expression" do
    @h.conditional_expression_arg.should == [99, 0]
  end

  it "inlines a method with optional params when all arguments are provided" do
    @h.optional_arg_provided.should == 8
  end
end
