require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/send_spec.rb
# Closure compilation link error: undefined __env__

describe "Send with closures" do
  it "handles send with closures" do
    obj = Object.new
    def obj.test
      lambda { self }
    end

    obj.send(:test).call.should == obj
  end
end
