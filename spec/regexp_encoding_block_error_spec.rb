require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/regexp/encoding_spec.rb line 46
# Parse error: Expected 'end' for 'do'-block
# Triggered by regex interpolation with nested regex: /#{/./}/

describe "Regexp with interpolated regex" do
  it "handles regex interpolation containing regex" do
    match = /#{/./}/.match("test")
    match.to_a.should == ["t"]
  end
end
