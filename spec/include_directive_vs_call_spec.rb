require_relative '../rubyspec/spec_helper'

# Test to verify that 'include' is correctly distinguished:
# 1. As a module directive when used inside a class: include ModuleName
# 2. As a regular method call when used outside a class: include(arg)

def include(x)
  x
end

module TestModule
  def module_method
    42
  end
end

class TestIncludeDirective
  include TestModule
end

describe "include" do
  it "works as a directive inside a class" do
    obj = TestIncludeDirective.new
    obj.module_method.should == 42
  end

  it "works as a method call outside a class" do
    # This should be treated as a method call, not a directive
    result = include(5)
    result.should == 5
  end
end
