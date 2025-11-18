require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/keyword_arguments_spec.rb
# Issue #36: Keyword argument shorthand

describe "Keyword arguments with shorthand" do
  it "handles keyword argument shorthand in various contexts" do
    x = 10
    h = {x:}
    h[:x].should == 10
  end
end
