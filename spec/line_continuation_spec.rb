require_relative '../rubyspec/spec_helper'

# Line continuation with backslash at end of line
# See: rubyspec/language/string_spec.rb:227
# Error: "Parse error: Expected: expression or 'end'"

describe "Line continuation" do
  it "allows backslash at end of line to continue" do
    x = 1 + \
        2
    x.should == 3
  end

  it "allows string concatenation across lines with backslash" do
    s = "hello " + \
        "world"
    s.should == "hello world"
  end
end
