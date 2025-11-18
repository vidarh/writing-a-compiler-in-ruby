require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/symbol_spec.rb
# Expression did not reduce to single value (2 values on stack)

describe "Symbol with expression reduction error" do
  it "handles symbol arrays" do
    arr = %w"one two three"
    arr.should == ["one", "two", "three"]
  end
end
