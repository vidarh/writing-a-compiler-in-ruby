require_relative '../rubyspec_helper'

# rescue inside do...end blocks
# See: rubyspec/language/block_spec.rb:342
# Error: "Parse error: Expected: 'end' for 'do'-block"

describe "do...end block with rescue" do
  it "supports rescue inside do...end block" do
    result = lambda do
      raise "error"
    rescue
      42
    end
    result.call.should == 42
  end

  it "supports rescue with exception class" do
    result = lambda do
      raise ArgumentError
    rescue ArgumentError
      99
    end
    result.call.should == 99
  end
end
