require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/singleton_class_spec.rb
# Assembly generation error: junk `[:sexp' after expression
# Triggered by class ::GlobalClass syntax

describe "Singleton class with global namespace" do
  it "defines class in global namespace" do
    class SingletonTestContainer
      class ::GlobalSingletonClass
      end
    end
    GlobalSingletonClass.should be_kind_of(Class)
  end
end
