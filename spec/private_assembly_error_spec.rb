require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/private_spec.rb
# Assembly generation error: junk `[:sexp' after expression
# Triggered by class ::GlobalClass syntax

describe "Private with global namespace class" do
  it "defines class in global namespace" do
    class PrivateTestContainer
      class ::GlobalPrivateClass
      end
    end
    GlobalPrivateClass.should be_kind_of(Class)
  end
end
