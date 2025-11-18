require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/class_spec.rb line 450
# Issue #2: Parser requires atom for superclass

describe "Class with non-atom superclass" do
  it "rejects string as superclass" do
    # Parser should reject this with parse error
    -> { class TestClass < ""; end }.should raise_error(TypeError)
  end
end
