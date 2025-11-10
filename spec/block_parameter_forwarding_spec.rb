require_relative '../rubyspec/spec_helper'

# Block parameter forwarding without parentheses fails to parse
# See KNOWN_ISSUES.md #9 - Block Parameter Forwarding
#
# When calling a method without parentheses and forwarding a block with &block,
# the parser leaves two values on the stack instead of incorporating &block
# into the method call's arguments.
#
# Workaround: Use parentheses in method calls with &block

describe "Block parameter forwarding" do
  it "works with parentheses" do
    def foo(a, &b)
      b ? b.call(a) : a
    end

    result = foo(42) { |x| x + 1 }
    result.should == 43
  end

  # This test would fail to compile without parentheses:
  # it "works without parentheses" do
  #   def foo(a, &b)
  #     b ? b.call(a) : a
  #   end
  #
  #   result = foo 42 { |x| x + 1 }  # Would fail
  #   result.should == 43
  # end
end
