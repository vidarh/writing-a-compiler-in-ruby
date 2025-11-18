require_relative '../rubyspec/spec_helper'

describe "The predefined standard objects" do
  it "includes ARGF" do
    Object.const_defined?(:ARGF).should == true
  end

  it "includes ARGV" do
    Object.const_defined?(:ARGV).should == true
  end

  it "includes a hash-like object ENV" do
    Object.const_defined?(:ENV).should == true
    ENV.respond_to?(:[]).should == true
  end
end

describe "The predefined standard object nil" do
  it "is an instance of NilClass" do
    nil.should be_kind_of(NilClass)
  end

  it "raises a SyntaxError if assigned to" do
    -> { eval("nil = true") }.should raise_error(SyntaxError, /Can't assign to nil/)
  end
end
