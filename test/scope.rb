require 'scope'
require 'function'
require 'set'

########### helper methods ###########

def global_scope
  gs = GlobalScope.new
  gs.globals << :my_global
  gs
end

def empty_global_scope
  GlobalScope.new
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

def func_scope
  FuncScope.new(function, global_scope)
end

def local_scope
  locals = {:local1 => 0, :local2 => 1}
  LocalVarScope.new(locals, func_scope)
end

def class_scope
  ClassScope.new(global_scope, "SampleClass", VTableOffsets.new)
end


############ start specs ############

describe GlobalScope do

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

describe LocalVarScope do

  it "should have no locals when none given" do
    ls = LocalVarScope.new([], nil)
    ls.get_arg(:some_var).should == [:addr, :some_var]
  end

  it "should find arguments in local scope" do
    ls = local_scope
    ls.get_arg(:local1).should == [:lvar, 0]
    ls.get_arg(:local2).should == [:lvar, 1]
  end

  it "should not find arguments in local scope, but in global" do
    ls = local_scope
    ls.get_arg(:undefined_arg).should == [:addr, :undefined_arg]
    ls.get_arg(:my_global).should == [:global, :my_global]
  end

end

describe VTableOffsets do

  # once the instance var amount is calculated by the compiler
  # we can easily change this helper method as well.
  def with_ivar_offset(offset)
    ClassScope::CLASS_IVAR_NUM + offset
  end

  it "should have an offset of 3 when created (:new and :__send__)" do
    vto = VTableOffsets.new
    vto.max.should == with_ivar_offset(3)
  end

  it "should return the correct clean_name when given an array" do
    vto = VTableOffsets.new
    vto.clean_name(:foo).should == :foo
    vto.clean_name([:foo, :bar, :baz]).should == :bar
  end

  it "should allocate the correct offset" do
    vto = VTableOffsets.new

    empty = vto.max

    vto.alloc_offset(:foo)
    vto.max.should == empty + 1

    vto.alloc_offset(:bar)
    vto.max.should == empty + 2

    # should not change when allocating twice
    vto.alloc_offset(:foo)
    vto.max.should == empty + 2
  end

  it "should get the correct offset" do
    vto = VTableOffsets.new

    vto.get_offset(:new).should == with_ivar_offset(0)
    vto.get_offset(:__send__).should ==  with_ivar_offset(1)

    off = vto.alloc_offset(:foo)
    vto.get_offset(:foo).should == off
  end

end


describe ClassScope do

  it "should contain @__class__ instance variable on creation" do
    cs = class_scope
    cs.instance_vars.include?(:@__class__).should == true
    cs.get_arg(:@__class__).should == [:ivar, 0]
  end

  it "should add the instance variable" do
    cs = class_scope
    cs.add_ivar(:@bar)
    cs.instance_vars.include?(:@bar).should == true
  end

  it "should find the instance variable" do
    cs = class_scope
    cs.add_ivar(:@foo)
    cs.instance_size.should == 2 # @__class__ is predefined
    cs.get_arg(:@foo).should == [:ivar, 1]
  end

  it "should not find an undefined arg" do
    cs = class_scope
    cs.get_arg(:undefined_var)[0].should == :possible_callm
  end

  it "should find a global variable" do
    cs = class_scope
    cs.get_arg(:my_global).should == [:possible_callm, :my_global]
  end

  it "should find a class variable" do
    cs = class_scope
    # this needs to get fixed, when class vars are actually stored correctly
    cs.get_arg(:@@class_var).should == [:cvar, "__classvar__#{cs.name}__class_var".to_sym]
  end

end
