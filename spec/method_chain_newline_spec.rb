require_relative '../rubyspec_helper'

# Issue #24 in KNOWN_ISSUES.md
# Method chaining across newlines not supported
# Error: "Missing value in expression / op: {callm/2 pri=98} / vstack: []"
# Affects: symbol_spec.rb:44

describe "Method chaining across newlines" do
  it "allows chaining when . starts new line" do
    # Minimal reproduction:
    # foo()
    #   .to_s
    def foo
      42
    end

    foo()
      .to_s
  end
end
