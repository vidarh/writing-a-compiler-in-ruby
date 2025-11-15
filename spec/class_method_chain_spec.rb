require_relative '../rubyspec_helper'

# Issue #22 in KNOWN_ISSUES.md
# Method chaining after class/module definitions not supported
# Error: "Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :class"
# Affects: metaclass_spec.rb:185

describe "Method chaining after class definition" do
  it "allows chaining .class after singleton class definition" do
    # Minimal reproduction: class << true; self; end.class
    # This should return Class
    class << true; self; end.class
  end
end
