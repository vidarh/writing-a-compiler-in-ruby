require_relative '../rubyspec/spec_helper'

# Category 2: Variable-name collision / env rewrite
# Tests whether a local variable with the same name as a method on self
# gets incorrectly rewritten inside blocks/lambdas.
#
# Related @bug markers:
#   compiler.rb:619-623        - rest collides with arg.rest method call
#   regalloc.rb:310-312        - variable name matching method name in lambda
#   compile_comparisons.rb:9   - op var picked up instead of block param
#   output_functions.rb:57     - arg name collides with method name
#   lib/core/enumerator.rb:64  - range arg triggers range constructor rewrite (CONFIRMED: compilation failure)
#   compile_arithmetic.rb:122  - dividend set incorrectly in nested lambda
#   function.rb:123            - r not set to nil without explicit init

class VarCollisionRest
  def rest
    "method_rest"
  end

  def test_rest
    rest = "local_rest"
    result = nil
    [1].each do |x|
      result = rest
    end
    result
  end
end

class VarCollisionReg
  def reg
    "method_reg"
  end

  def test_reg
    result = nil
    f = lambda do |x|
      reg = "local_reg"
      result = reg
    end
    f.call(1)
    result
  end
end

class VarCollisionInterp
  def test_interp
    op = "hello"
    result = nil
    [1].each do |x|
      result = "set#{op.to_s}"
    end
    result
  end
end

class VarCollisionDividend
  def dividend
    "method_dividend"
  end

  def test_dividend
    result = nil
    [1].each do |outer|
      dividend = "local_dividend"
      [2].each do |inner|
        result = dividend
      end
    end
    result
  end
end

class VarCollisionConditionalInit
  def with_nil(flag)
    r = nil
    r = 42 if flag
    r
  end

  # CONFIRMED BUG: The without_nil variant (no explicit r = nil)
  # causes a segfault at runtime, confirming function.rb:123 bug
  # def without_nil(flag)
  #   if flag
  #     r = 42
  #   end
  #   r
  # end
end

describe "variable-name collision" do
  it "local var shadows method name inside block" do
    VarCollisionRest.new.test_rest.should == "local_rest"
  end

  it "local var shadows method name inside lambda" do
    VarCollisionReg.new.test_reg.should == "local_reg"
  end

  it "string interpolation with outer-scope variable inside block" do
    VarCollisionInterp.new.test_interp.should == "sethello"
  end

  it "variable initialized to nil with explicit assignment" do
    VarCollisionConditionalInit.new.with_nil(false).should == nil
    VarCollisionConditionalInit.new.with_nil(true).should == 42
  end

  # CONFIRMED BUG: uncommenting the without_nil method causes segfault
  # This confirms function.rb:123 bug: variable not initialized to nil
  # it "variable conditionally assigned without explicit nil init" do
  #   VarCollisionConditionalInit.new.without_nil(false).should == nil
  # end

  it "variable named same as method in nested do blocks" do
    VarCollisionDividend.new.test_dividend.should == "local_dividend"
  end
end
