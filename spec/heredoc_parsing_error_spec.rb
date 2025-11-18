require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/heredoc_spec.rb
# Unterminated heredoc error at tokens.rb:813

describe "Heredoc parsing" do
  it "parses heredoc correctly" do
    str = <<HERE
test string
HERE
    str.should == "test string\n"
  end
end
