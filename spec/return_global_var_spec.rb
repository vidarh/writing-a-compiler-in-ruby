require_relative '../rubyspec/spec_helper'

describe "Return with global variable in require" do
  it "handles require with global variable argument" do
    $spec_filename = "test_file.rb"
    # This should parse successfully even if require fails at runtime
    lambda { require $spec_filename }.should raise_error(LoadError)
  end
end
