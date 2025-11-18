require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/method_spec.rb
# Issue #36: Keyword argument shorthand in method calls

describe "Method calls with keyword argument shorthand" do
  it "handles keyword argument shorthand" do
    def receiver(x:)
      x * 2
    end

    x = 21
    # The shorthand syntax {x:} is the issue
    h = {x:}
    h[:x].should == 21
  end
end
