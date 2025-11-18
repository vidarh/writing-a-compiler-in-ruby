require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/for_spec.rb
# Closure compilation link error: undefined __env__ and __closure__
# Triggered by for loop with class variable as iterator

describe "For loop with class variable iterator" do
  it "allows a class variable as iterator name" do
    class ForTestClass
      m = [1, 2, 3]
      n = 0
      for @@var in m
        n += 1
      end
      @@var.should == 3
      n.should == 3
    end
  end
end
