require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/constants_spec.rb
# Error: "Somewhere calling #compile_exp when they should be calling #compile_eval_arg?"
# Related to singleton class with constants

describe "Constants in singleton classes" do
  it "handles constants in singleton classes" do
    objs = [Object.new, Object.new]
    2.times do |i|
      obj = objs[i]
      $spec_i = i
      class << obj
        CONST = ($spec_i + 1)
        def foo
          CONST
        end
      end
    end
    objs[0].foo.should == 1
  end
end
