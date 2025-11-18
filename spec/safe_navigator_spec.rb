require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/safe_navigator_spec.rb
# Safe navigation operator &. not supported
# Error: "Missing value in expression / op: {&/2 pri=11}"

describe "Safe navigation operator" do
  it "handles safe navigation with nil" do
    result = nil&.unknown
    result.should == nil
  end
end
