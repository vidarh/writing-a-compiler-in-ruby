require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/regexp/encoding_spec.rb
# Parse error: Expected 'end' for 'do'-block

describe "Regexp encoding with blocks" do
  it "handles regexp in blocks" do
    result = [1, 2, 3].map do |x|
      /test/
      x * 2
    end
    result.should == [2, 4, 6]
  end
end
