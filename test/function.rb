require 'function'
require 'scope'

describe Arg do

  it "should have a variable amount of arguments" do
    a = Arg.new("arg1", :rest)
    a.rest?.should be true
  end

  it "should be of type :argaddr" do
    a = Arg.new("arg2", :rest)
    a.type.should be :argaddr
  end

  it "should be of type :arg" do
    a = Arg.new("arg3")
    a.type.should be :arg
  end

end


describe Function do

  def function_with_args
    args = [:arg1, :arg2, :arg3]
    body = [:let, [:foo], [[:printf, "hello"]]]
    f = Function.new(args, body, nil)
  end

  it "should return the correct number of arguments" do
    f = function_with_args
    f.get_arg(:numargs).should match_array([:int, 3])
  end

  it "should find an arg within argument list" do
    f = function_with_args
    f.get_arg(:arg1).should match_array([:arg, 0])
  end

  it "should not have a variable argument list" do
    f = function_with_args
    f.rest?.should be false
  end

  it "should have a variable argument list" do
    f = Function.new([:arg1, [:args, :rest]], [], nil)
    f.rest?.should be true
  end

end
