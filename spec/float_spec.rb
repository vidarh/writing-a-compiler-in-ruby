require_relative '../rubyspec/spec_helper'

# KNOWN_ISSUES #7: Float support limited

describe "Float operations" do
  it "should support float literals" do
    x = 3.14
    x.should == 3.14
  end

  it "should support float arithmetic" do
    result = 3.14 + 2.86
    result.should == 6.0
  end

  it "should support float comparison" do
    (3.14 > 2.0).should == true
  end

  it "should support Integer#fdiv" do
    result = 10.fdiv(3)
    result.should == 3.3333333333333335
  end

  it "should support division by float" do
    result = 10 / 2.0
    result.should == 5.0
  end
end
