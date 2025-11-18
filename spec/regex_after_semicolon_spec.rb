require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/case_spec.rb line 392
# Issue #38: Regex after semicolon parsed as division (DEFERRED)

describe "Regex after semicolon" do
  it "parses regex after semicolon in when clause" do
    result = case 42
    when (raise if 2+2 == 3; /a/)
      :matched
    else
      :not_matched
    end
    result.should == :not_matched
  end
end
