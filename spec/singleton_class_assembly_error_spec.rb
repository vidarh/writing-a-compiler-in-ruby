require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/singleton_class_spec.rb
# Assembly generation error: junk `[:sexp' after expression

describe "Singleton class" do
  it "defines singleton class methods" do
    obj = "test"
    class << obj
      def custom_method
        :custom
      end
    end
    obj.custom_method.should == :custom
  end
end
