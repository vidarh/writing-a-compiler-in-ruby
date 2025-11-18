require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/module_spec.rb
# Issue #46: Nested constant assignments in modules

module ModSpecs
  module Inner
  end
end

describe "Module with nested constant assignment" do
  it "handles nested module constant assignments" do
    ModSpecs::Inner::VALUE = 100
    ModSpecs::Inner::VALUE.should == 100
  end
end
