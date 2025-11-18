require_relative '../rubyspec/spec_helper'

module TestMod
  def test_method
    42
  end
end

class TestClass
  include TestMod
end

describe "simple include test" do
  it "includes module in class" do
    obj = TestClass.new
    obj.test_method.should == 42
  end
end
