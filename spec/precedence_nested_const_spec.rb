require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/precedence_spec.rb
# Issue #46: Nested constant assignments with precedence

module PrecSpecs
  module Nested
  end
end

describe "Precedence with nested constant assignment" do
  it "handles complex nested constant assignments" do
    PrecSpecs::Nested::CONST = 1 + 2 * 3
    PrecSpecs::Nested::CONST.should == 7
  end
end
