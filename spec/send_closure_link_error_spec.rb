require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/send_spec.rb lines 559, 573
# Closure compilation link error: undefined __env__
# Triggered by def self.m with splat and block forwarding

describe "Send with splat and block forwarding" do
  it "handles def self.m with splat and block args" do
    def self.test_method(*args, &block)
      [args, block]
    end

    args = [1, 2]
    test_method(*args, &args.pop).should == [[1, 2], 2]
  end
end
