require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/super_spec.rb
# Closure compilation link error: undefined Module reference

class SuperBase
  def method
    "base"
  end
end

class SuperDerived < SuperBase
  def method
    lambda { super }.call
  end
end

describe "Super with closures" do
  it "handles super inside closures" do
    SuperDerived.new.method.should == "base"
  end
end
