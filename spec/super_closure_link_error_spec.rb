require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/super_spec.rb lines 340, 1013
# Closure compilation link error: undefined Module reference
# Triggered by Class.new do ... end

describe "Super with Class.new block" do
  it "handles super in dynamically created class" do
    foo_class = Class.new do
      def bar
        "bar"
      end
    end

    foo_class.new.bar.should == "bar"
  end
end
