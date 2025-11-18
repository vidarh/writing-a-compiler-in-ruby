require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/metaclass_spec.rb
# Assembly generation error: junk `[:sexp' after expression
# Triggered by class ::A (global namespace class definition)

describe "Metaclass" do
  it "defines global namespace class from within another context" do
    class TestMetaclass
      class ::A; end
    end
    A.should be_kind_of(Class)
  end
end
