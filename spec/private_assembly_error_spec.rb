require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/private_spec.rb
# Assembly generation error: junk `[:sexp' after expression

class PrivateTestClass
  private

  def private_method
    :private_result
  end

  public

  def call_private
    private_method
  end
end

describe "Private methods" do
  it "can call private methods from same class" do
    PrivateTestClass.new.call_private.should == :private_result
  end
end
