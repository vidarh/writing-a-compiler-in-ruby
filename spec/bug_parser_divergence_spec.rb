require_relative '../rubyspec/spec_helper'

# Category 6: Parser divergence between MRI and self-hosted
# Tests constructs where the self-hosted parser produces different
# results than MRI parsing.
#
# Related @bug markers:
#   parser.rb:797       - MRI needs E[pos].concat(ret) for Arrays
#   compiler.rb:1231    - @e.with_local(vars.size+1) parsed incorrectly

class ParserTestObj
  def take(n)
    n
  end

  def foo
    self
  end

  def bar(n)
    n
  end
end

describe "parser divergence" do
  it "method call with arithmetic expression as argument" do
    arr = [1, 2, 3]
    ParserTestObj.new.take(arr.size + 1).should == 4
  end

  it "method call with arithmetic on method result inside block" do
    result = nil
    arr = [1, 2, 3]
    [1].each do |x|
      result = ParserTestObj.new.take(arr.size + 1)
    end
    result.should == 4
  end

  it "method call with subtraction on method result" do
    arr = [1, 2, 3]
    ParserTestObj.new.take(arr.size - 1).should == 2
  end

  it "chained method call with arithmetic" do
    arr = [1, 2, 3]
    ParserTestObj.new.foo.bar(arr.size + 1).should == 4
  end

  it "conditional array concat based on type" do
    base = [1, 2]
    extra = [3, 4]
    result = base
    if extra.is_a?(Array)
      result = base.concat(extra)
    end
    result.should == [1, 2, 3, 4]
  end
end
