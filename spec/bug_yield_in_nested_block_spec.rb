require_relative '../rubyspec/spec_helper'

# Category 1: yield/block.call in nested contexts
# Tests whether yield works inside nested blocks/lambdas when the enclosing
# method takes &block.
#
# Related @bug markers:
#   emitter.rb:409-410 - yield does not work here (block.call(c.reg))
#   emitter.rb:417-418 - yield does not work here (block.call(r))
#   globals.rb:46-48   - yield gets turned into calling "comma"
#   compile_calls.rb:323 - block forwarding + yield interaction

class YieldHelper
  def with_thing
    [1].each do |x|
      yield x
    end
  end

  def with_thing_via_block(&block)
    [1].each do |x|
      yield x
    end
  end

  def multi_yield
    pairs = [[10, 20], [30, 40]]
    pairs.each do |pair|
      yield pair[0], pair[1]
    end
  end

  def with_conditional(flag, &block)
    if flag
      [1].each do |x|
        yield x + 100
      end
    else
      [2].each do |x|
        yield x + 200
      end
    end
  end

  def doubly_nested
    [1].each do |x|
      [2].each do |y|
        yield x + y
      end
    end
  end

  def yield_no_args
    [1].each do |x|
      yield
    end
  end
end

describe "yield in nested blocks" do
  it "yields from inside a nested do-block" do
    result = nil
    YieldHelper.new.with_thing do |v|
      result = v
    end
    result.should == 1
  end

  it "yields with multiple arguments from nested block" do
    results = []
    YieldHelper.new.multi_yield do |a, b|
      results << a
      results << b
    end
    results.should == [10, 20, 30, 40]
  end

  it "yields from method that received block via &block, inside conditional" do
    result = nil
    YieldHelper.new.with_conditional(true) do |v|
      result = v
    end
    result.should == 101

    result = nil
    YieldHelper.new.with_conditional(false) do |v|
      result = v
    end
    result.should == 202
  end

  it "yields from doubly-nested block" do
    result = nil
    YieldHelper.new.doubly_nested do |v|
      result = v
    end
    result.should == 3
  end

  it "yields with no arguments from nested block" do
    called = false
    YieldHelper.new.yield_no_args do
      called = true
    end
    called.should == true
  end
end
