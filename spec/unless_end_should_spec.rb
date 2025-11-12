require_relative '../rubyspec/spec_helper'

describe "unless end.should without parentheses" do
  it "works with unless end.should" do
    unless false
      42
    end.should == 42
  end
end
