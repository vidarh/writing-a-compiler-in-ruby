require_relative '../rubyspec/spec_helper'

# Category 5: Self-recursive lambda / method extraction
# Tests whether self-recursive lambdas and iteration-with-method-call
# lambdas compile correctly.
#
# Related @bug markers:
#   compiler.rb:563      - compile_case_test was a self-recursive lambda
#   compile_class.rb:113 - compile_ary_do extracted for eigenclass
#   transform.rb:1088    - build_class_scopes_for_class extracted

class LambdaIter
  def process(item)
    item * 2
  end

  def run(items)
    results = []
    items.each do |e|
      results << process(e)
    end
    results
  end
end

describe "self-recursive lambda and method extraction" do
  it "self-recursive lambda computes factorial" do
    # Use if/else instead of ternary (ternary may be bugged, Category 3)
    fact = nil
    fact = lambda do |n|
      if n <= 1
        1
      else
        n * fact.call(n - 1)
      end
    end
    fact.call(5).should == 120
  end

  it "lambda that iterates and calls a method on self" do
    LambdaIter.new.run([1, 2, 3]).should == [2, 4, 6]
  end

  it "lambda assigned to local called multiple times" do
    double = lambda { |x| x * 2 }
    double.call(3).should == 6
    double.call(5).should == 10
    double.call(7).should == 14
  end

  it "inline form: items.each calling self.method inside a method" do
    obj = LambdaIter.new
    results = []
    [10, 20].each do |e|
      results << obj.process(e)
    end
    results.should == [20, 40]
  end

  it "mutually recursive lambdas" do
    is_even = nil
    is_odd = nil
    is_even = lambda do |n|
      if n == 0
        true
      else
        is_odd.call(n - 1)
      end
    end
    is_odd = lambda do |n|
      if n == 0
        false
      else
        is_even.call(n - 1)
      end
    end
    is_even.call(4).should == true
    is_odd.call(3).should == true
    is_even.call(3).should == false
  end
end
