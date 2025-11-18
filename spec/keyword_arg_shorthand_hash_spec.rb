require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/hash_spec.rb line 307
# Issue #36: Keyword argument shorthand not supported

describe "Keyword argument shorthand in hash literals" do
  it "supports {a:} as shorthand for {a: a}" do
    a = 42
    h = {a:}
    h[:a].should == 42
  end
end
