require_relative '../rubyspec/spec_helper'

describe "The predefined standard object nil" do
  it "is an instance of NilClass" do
    nil.should be_kind_of(NilClass)
  end

  it "raises a SyntaxError if assigned to" do
    -> { eval("nil = true") }.should raise_error(SyntaxError, /Can't assign to nil/)
  end
end
