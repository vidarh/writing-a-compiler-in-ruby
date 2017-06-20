require_relative '../function'
require_relative '../scope'

describe Arg do

  it "should have a variable amount of arguments" do
    a = Arg.new(:arg1, :rest)
    a.rest?.should be true
  end

  it "should be of type :argaddr if it is a 'splat' argument (*arg)" do
    a = Arg.new(:arg2, :rest)
    a.type.should be :argaddr
  end

  it "should be of type :arg if it is a regular argument" do
    a = Arg.new(:arg3)
    a.type.should be :arg
  end

end


describe Function do

  def function_with_args
    args = [:arg1, :arg2, :arg3]
    body = [:let, [:foo], [[:printf, "hello"]]]
    f = Function.new(nil,args, body, nil, "break_label")
  end

  it "#get_arg(:numargs) should return a 'fake' local variable (lvar) lookup with offset -1" do
    f = function_with_args
    f.get_arg(:numargs).should match_array([:lvar, -1])
  end

  it "should find a named argument within argument list" do
    f = function_with_args
    f.get_arg(:arg1).should match_array([:arg, 0])
  end

  it "should not have a variable argument list if no splat is present" do
    f = function_with_args
    f.rest?.should be false
  end

  it "should have a variable argument list if splat is present" do
    f = Function.new(nil,[:arg1, [:args, :rest]], [], nil, "break_label")
    f.rest?.should be true
  end

end
