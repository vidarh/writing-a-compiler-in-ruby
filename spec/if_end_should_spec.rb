require_relative '../rubyspec/spec_helper'

describe "if end.should without parentheses" do
  it "works with if end.should" do
    if true
      42
    end.should == 42
  end
end
