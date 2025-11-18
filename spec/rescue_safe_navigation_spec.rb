require_relative '../rubyspec/spec_helper'

describe "Rescue with safe navigation operator" do
  it "captures exception with safe navigation in binding" do
    class SafeNavCaptor
      attr_accessor :captured_error

      def capture(msg)
        raise msg
      rescue => self&.captured_error
        :caught
      end
    end

    captor = SafeNavCaptor.new
    captor.capture("test error").should == :caught
    captor.captured_error.message.should == "test error"
  end
end
