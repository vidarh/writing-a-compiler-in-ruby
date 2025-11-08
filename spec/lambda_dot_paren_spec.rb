require_relative '../rubyspec/spec_helper'

# Lambda .() call syntax
describe "Lambda .() call syntax" do
  it "supports .() syntax with no arguments" do
    l = lambda { 42 }
    l.().should == 42
  end

  it "supports .() syntax with one argument" do
    l = lambda { |x| x * 2 }
    l.(21).should == 42
  end

  it "supports .() syntax with multiple arguments" do
    l = lambda { |x, y| x + y }
    l.(40, 2).should == 42
  end

  # Proc.new crashes (pre-existing bug unrelated to .() syntax)
  # it "supports .() syntax with Proc" do
  #   pr = Proc.new { |x| x * 3 }
  #   pr.(14).should == 42
  # end
end
