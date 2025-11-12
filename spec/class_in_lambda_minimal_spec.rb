require_relative '../rubyspec/spec_helper'

describe "Class definition inside lambda (minimal)" do
  it "allows defining classes inside lambdas" do
    result = 0

    # Define and call lambda immediately
    result = (lambda do
      class MinimalTestClass
        def value
          42
        end
      end

      MinimalTestClass.new.value
    end).call

    result.should == 42
  end
end
