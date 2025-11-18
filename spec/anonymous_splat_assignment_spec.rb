require_relative '../rubyspec/spec_helper'

describe "Anonymous splat assignment" do
  it "consumes values for an anonymous splat" do
    (* = 1).should == 1
  end
end
