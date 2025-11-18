require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/optional_assignments_spec.rb line 563
# Issue #45: Splat with begin block in array indexing

describe "Optional assignments with splat and begin" do
  it "handles splat with begin block in array indexing" do
    h = {k: 10}
    h[*begin [:k] end] ||= 20
    h[:k].should == 10
  end
end
