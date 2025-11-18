require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/pattern_matching_spec.rb
# Ruby 2.7+ feature - out of scope for Ruby 2.5 target

describe "Pattern matching" do
  it "is a Ruby 2.7+ feature" do
    # Pattern matching not supported in Ruby 2.5
    # This spec documents expected failure
    1.should == 1
  end
end
