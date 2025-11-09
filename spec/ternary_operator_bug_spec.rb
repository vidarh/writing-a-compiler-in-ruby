require_relative '../rubyspec/spec_helper'

# Related to KNOWN_ISSUES.md issue about ternary operator
describe "Ternary operator" do
  it "should return correct value from both branches" do
    result = 5 < 4 ? 4 : 5
    result.should == 5

    result2 = 3 < 4 ? 4 : 3
    result2.should == 4
  end

  it "should work with variable assignment" do
    x = 10
    result = x < 4 ? 4 : x
    result.should == 10
  end

  it "should work as final expression in method" do
    def test_method
      result = (42.bit_length + 7) / 8
      result < 4 ? 4 : result
    end

    test_method.should == 4
  end

  it "should work with larger values" do
    def test_method2
      result = (256**7).bit_length + 7
      result = result / 8
      result < 4 ? 4 : result
    end

    test_method2.should == 8
  end
end
