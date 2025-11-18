require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/module_spec.rb
# Error: "Expected an argument on left hand side of assignment"
# Nested constant assignment inside closure

module ModSpecs
  module CS1
  end
end

describe "Module with nested constant assignment in closure" do
  it "handles nested constant assignment in lambda" do
    lambda {
      ModSpecs::CS1::CONST = 1
    }.call
    ModSpecs::CS1::CONST.should == 1
  end
end
