require_relative '../rubyspec/spec_helper'

describe "Global variable $\"" do
  it "is accessible and refers to LOADED_FEATURES" do
    $".should equal $LOADED_FEATURES
  end

  it "is read-only" do
    lambda {
      $" = []
    }.should raise_error(NameError, '$" is a read-only variable')
  end
end
