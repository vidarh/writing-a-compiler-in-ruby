require_relative '../rubyspec/spec_helper'

describe "Regex literal tokenization" do
  it "parses regex after assignment" do
    x = /abc/
    x.class.should == Regexp
  end

  it "parses regex after semicolon" do
    y = 1; x = /def/
    x.class.should == Regexp
  end

  it "parses division after identifier" do
    a = 10
    b = 5
    c = a / b
    c.should == 2
  end

  it "parses division after closing paren" do
    result = (10) / 2
    result.should == 5
  end
end
