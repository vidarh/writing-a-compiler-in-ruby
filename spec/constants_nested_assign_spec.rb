require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/constants_spec.rb
# Error: "Somewhere calling #compile_exp when they should be calling #compile_eval_arg?"
# Triggered by singleton class with constant at module level

module ConstantsSpec
  CS_SINGLETON1 = Object.new
  class << CS_SINGLETON1
    CONST = 1
    def foo
      CONST
    end
  end
end

describe "Constants in singleton classes" do
  it "handles constants in singleton classes" do
    ConstantsSpec::CS_SINGLETON1.foo.should == 1
  end
end
