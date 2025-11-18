require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/def_spec.rb
# Issue #36: Keyword argument shorthand in method definitions

describe "Def with keyword argument shorthand" do
  it "handles keyword argument definitions" do
    def test_method(a:)
      a
    end

    # The shorthand {a:} in hash literals is the issue
    a = 42
    h = {a:}
    h[:a].should == 42
  end
end
