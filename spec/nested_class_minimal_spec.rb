require_relative '../rubyspec/spec_helper'

module NestedClassTest
end

class NestedClassTest::MyClass
  def test
    42
  end
end

describe "Nested class syntax" do
  it "allows defining and using class Foo::Bar" do
    NestedClassTest::MyClass.new.test.should == 42
  end
end
