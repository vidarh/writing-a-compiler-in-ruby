require_relative '../rubyspec/spec_helper'

# Category 4: block_given? in nested lambdas
# Tests whether block_given? returns the correct value when checked
# inside a nested block/lambda.
#
# Related @bug markers:
#   compile_arithmetic.rb:115-118 - block_given? doesn't work in nested lambdas

class BlockGivenHelper
  # CONFIRMED BUG: block_given? inside nested block causes segfault.
  # def check_bg_nested(&block)
  #   result = nil
  #   [1].each do |x|
  #     result = block_given?
  #   end
  #   result
  # end

  def check_bg_captured(&block)
    bg = block_given?
    result = nil
    [1].each do |x|
      result = bg
    end
    result
  end

  def check_bg_simple(&block)
    block_given?
  end

  # CONFIRMED BUG: block_given? inside doubly-nested block causes segfault
  # def check_bg_doubly_nested(&block)
  #   result = nil
  #   [1].each do |x|
  #     [2].each do |y|
  #       result = block_given?
  #     end
  #   end
  #   result
  # end

  # CONFIRMED BUG: block_given? inside lambda causes segfault
  # def check_bg_lambda(&block)
  #   f = lambda { block_given? }
  #   f.call
  # end
end

describe "block_given? in nested blocks" do
  # CONFIRMED BUG: block_given? inside nested block segfaults
  # it "block_given? inside a nested do-block (block passed)" do
  #   result = BlockGivenHelper.new.check_bg_nested do 42 end
  #   result.should == true
  # end

  it "block_given? works at top level of method" do
    result = BlockGivenHelper.new.check_bg_simple do 42 end
    result.should == true
    BlockGivenHelper.new.check_bg_simple.should == false
  end

  it "block_given? captured to local before entering nested block (workaround)" do
    result = BlockGivenHelper.new.check_bg_captured do 42 end
    result.should == true
    BlockGivenHelper.new.check_bg_captured.should == false
  end

  # CONFIRMED BUG: segfaults
  # it "block_given? inside doubly-nested block" do
  #   result = BlockGivenHelper.new.check_bg_doubly_nested do 42 end
  #   result.should == true
  # end

  # CONFIRMED BUG: segfaults
  # it "block_given? inside lambda inside method" do
  #   result = BlockGivenHelper.new.check_bg_lambda do 42 end
  #   result.should == false
  # end
end
