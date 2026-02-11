require_relative '../rubyspec/spec_helper'

describe "Heredoc interpolation" do
  it "handles basic interpolation" do
    val = "world"
    s = <<HERE
hello #{val}
HERE
    s.should == "hello world\n"
  end
end
