require_relative '../rubyspec/spec_helper'

describe "Global namespace operator ::" do
  it "works in simple assignments" do
    x = ::String
    x.should == String
  end

  it "works with nested constant access" do
    class TestClass
      VALUE = 42
    end

    x = ::TestClass::VALUE
    x.should == 42
  end
end
