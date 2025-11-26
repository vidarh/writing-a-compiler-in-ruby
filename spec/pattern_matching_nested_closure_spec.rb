require_relative '../rubyspec/spec_helper'

# KNOWN ISSUE: Pattern-bound variables not captured in nested closures
# See docs/KNOWN_ISSUES.md - "Pattern Matching with Nested Closures"
#
# Pattern-bound variables inside closures are not properly added to __env__
# because find_vars runs before rewrite_pattern_matching creates the bindings.

describe "Pattern matching with nested closures" do
  it "should capture pattern-bound variables in nested closures (KNOWN FAILURE)" do
    result = nil
    1.times {
      case {x: 42}
      in {x:}
        1.times { result = x }
      end
    }
    result.should == 42
  end
end
