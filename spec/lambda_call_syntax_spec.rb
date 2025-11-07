require_relative '../rubyspec/spec_helper'

# KNOWN_ISSUES #6: Lambda .() and [] call syntax not supported

describe "Lambda call syntax" do
  it "supports .call syntax" do
    l = lambda { 42 }
    l.call.should == 42
  end

  it "supports .call with arguments" do
    l = lambda { |x| x * 2 }
    l.call(21).should == 42
  end

  it "supports [] syntax for calling lambdas" do
    l = lambda { 42 }
    l[].should == 42
  end

  it "supports [] syntax with arguments" do
    l = lambda { |x| x * 2 }
    l[21].should == 42
  end
end
