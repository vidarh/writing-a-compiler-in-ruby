require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/predefined_spec.rb
# Assembly error: symbol __method_Object_method_missing is already defined

describe "Predefined methods" do
  it "handles method_missing" do
    obj = Object.new
    def obj.method_missing(name, *args)
      "missing: #{name}"
    end
    obj.unknown_method.should == "missing: unknown_method"
  end
end
