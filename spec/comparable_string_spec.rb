require_relative '../rubyspec/spec_helper'

describe "String comparison via Comparable" do
  it "'a' < 'b' returns true" do
    ("a" < "b").should == true
  end

  it "'b' < 'a' returns false" do
    ("b" < "a").should == false
  end

  it "'a' <= 'a' returns true" do
    ("a" <= "a").should == true
  end

  it "'a' <= 'b' returns true" do
    ("a" <= "b").should == true
  end

  it "'b' <= 'a' returns false" do
    ("b" <= "a").should == false
  end

  it "'b' > 'a' returns true" do
    ("b" > "a").should == true
  end

  it "'a' > 'b' returns false" do
    ("a" > "b").should == false
  end

  it "'a' >= 'a' returns true" do
    ("a" >= "a").should == true
  end

  it "'z' >= 'a' returns true" do
    ("z" >= "a").should == true
  end

  it "'a' >= 'z' returns false" do
    ("a" >= "z").should == false
  end

  it "'hello'.between?('a', 'z') returns true" do
    "hello".between?("a", "z").should == true
  end

  it "'a'.between?('b', 'z') returns false" do
    "a".between?("b", "z").should == false
  end
end

describe "String comparison edge cases" do
  it "String == still uses String's own implementation" do
    ("hello" == "hello").should == true
  end

  it "strings of different lengths" do
    ("ab" < "abc").should == true
  end

  it "strings of different lengths reversed" do
    ("abc" > "ab").should == true
  end

  it "empty string comparison" do
    ("" < "a").should == true
  end

  it "string compared to non-string with < returns nil" do
    ("a" < 1).should == nil
  end
end
