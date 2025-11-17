require_relative '../rubyspec/spec_helper'

describe "Compound assignment operators" do
  it "supports *= operator" do
    a = 5
    a *= 3
    a.should == 15
  end

  it "supports /= operator" do
    a = 20
    a /= 4
    a.should == 5
  end

  it "supports %= operator" do
    a = 10
    a %= 3
    a.should == 1
  end

  it "supports **= operator" do
    a = 2
    a **= 3
    a.should == 8
  end

  it "supports &= operator" do
    a = 15
    a &= 7
    a.should == 7
  end

  it "supports |= operator" do
    a = 8
    a |= 3
    a.should == 11
  end

  it "supports ^= operator" do
    a = 15
    a ^= 5
    a.should == 10
  end

  it "supports <<= operator" do
    a = 2
    a <<= 3
    a.should == 16
  end

  it "supports >>= operator" do
    a = 16
    a >>= 2
    a.should == 4
  end

  it "supports &&= operator" do
    a = 5
    a &&= 10
    a.should == 10

    b = nil
    b &&= 10
    b.should == nil

    c = false
    c &&= 10
    c.should == false
  end
end
