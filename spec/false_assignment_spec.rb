require_relative '../rubyspec/spec_helper'

describe "The predefined standard object false" do
  it "raises a SyntaxError if assigned to" do
    -> { eval("false = nil") }.should raise_error(SyntaxError, /Can't assign to false/)
  end
end
