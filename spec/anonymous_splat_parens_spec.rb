require_relative '../rubyspec_helper'

# Issue #23 in KNOWN_ISSUES.md
# Anonymous splat in parentheses not supported
# Error: "Missing value in expression / {splat/1 pri=8}"
# Affects: variables_spec.rb:410

describe "Anonymous splat assignment" do
  it "works inside parentheses as an expression" do
    # Minimal reproduction: (* = 1)
    # This should return 1
    (* = 1)
  end
end
