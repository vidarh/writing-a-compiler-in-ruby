require_relative '../rubyspec/spec_helper'

describe "Until end.should pattern" do
  it "works with i = i + 1" do
    i = 0
    until i > 9
      i = i + 1
    end.should == nil
  end

  it "works with i += 1" do
    i = 0
    until i > 9
      i += 1
    end.should == nil
  end
end
