require_relative '../rubyspec/spec_helper'

describe "Test 77 minimal" do
  it "does not include the current directory" do
    $:.should_not include(".")
  end
end
