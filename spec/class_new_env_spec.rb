require_relative '../rubyspec/spec_helper'

describe "Class.new with block in closure" do
  it "defines methods correctly" do
    binary_plus = Class.new(String) do
      alias_method :plus, :+
      def +(a)
        plus(a) + "!"
      end
    end
    s = binary_plus.new("a")
    (s+s).should == "aa!"
  end
end
