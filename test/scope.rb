require 'scope'
require 'function'
require 'set'

describe GlobalScope do

  def empty_global_scope
    GlobalScope.new
  end

  it "should not have any globals defined at creation" do
    gs = empty_global_scope
    gs.globals.should be_empty
  end

  it "should contain a global" do
    gs = empty_global_scope
    gs.globals << :some_global
    gs.get_arg(:some_global).should == [:global, :some_global]
  end

  it "should not contain a certain global" do
    gs = empty_global_scope
    gs.get_arg(:some_global).should == [:addr, :some_global]
  end

end


describe FuncScope do

  def global_scope
    gs = GlobalScope.new
    gs.globals << :my_global
    gs
  end

  def function
    args = [:arg1, :arg2, :arg3]
    body = [[:printf, "hello, world"]]
    f = Function.new(args, body)
  end

  def method
    args = [:arg1, :arg2, :arg3]
    body = [[:printf, "hello, world"]]
    gs = global_scope
    cscope = ClassScope.new(gs, "TestClass", 0)
    f = Function.new(args, body, cscope)
  end

  it "should not have a variable amount of arguments" do
    f = function
    fs = FuncScope.new(f, global_scope)
    fs.rest?.should == false
  end

  it "should find an argument within its function scope" do
    f = function
    fs = FuncScope.new(f, nil)
    fs.get_arg(:arg3).should == [:arg, 2]
  end

  it "should find an argument in the outer (global) scope" do
    f = function
    fs = FuncScope.new(f, global_scope)
    fs.get_arg(:my_global).should == [:global, :my_global]
    fs.get_arg(:undefined_arg).should == [:addr, :undefined_arg]
  end

end
