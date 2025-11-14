require_relative '../rubyspec/spec_helper'

# Method definition inside do...end block
# See: rubyspec/language/block_spec.rb:70
# Error: "Parse error: Expected: 'end' for 'do'-block"
# Root cause: Parser sees 'end' from method definition and thinks it closes the do block

describe "Method definition inside do...end block" do
  it "allows method definition inside do block" do
    result = nil
    lambda do
      def helper
        42
      end
      result = helper
    end.call
    result.should == 42
  end

  it "handles nested ends correctly" do
    # This is the pattern from block_spec.rb:
    # before :all do
    #   def m(a) yield a end
    # end
    x = nil
    lambda do
      def simple(v)
        v * 2
      end
      x = simple(21)
    end.call
    x.should == 42
  end
end
