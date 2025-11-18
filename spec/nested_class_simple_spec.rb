require_relative '../rubyspec/spec_helper'

module NestedClassTest
end

class NestedClassTest::MyClass
  def test
    42
  end
end

module NestedModuleTest
end

module NestedModuleTest::MyModule
  def self.test
    99
  end
end

module NestedIncludeTest
end

module NestedIncludeTest::Mixin
  def mixed_method
    123
  end
end

class TestClass
  include NestedIncludeTest::Mixin
end

describe "Nested class syntax" do
  it "allows defining class Foo::Bar" do
    NestedClassTest::MyClass.new.test.should == 42
  end

  it "allows defining module Foo::Bar" do
    NestedModuleTest::MyModule.test.should == 99
  end

  it "allows including nested modules" do
    TestClass.new.mixed_method.should == 123
  end
end
