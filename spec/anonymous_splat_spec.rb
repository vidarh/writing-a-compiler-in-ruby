require_relative '../rubyspec_helper'

# Anonymous splat assignment - Ruby 2.7+ feature
# See: rubyspec/language/variables_spec.rb:410
# Error: "Missing value in expression / {splat/1 pri=8}"

describe "Anonymous splat" do
  it "consumes values for an anonymous splat" do
    (* = 1).should == 1
  end
end
