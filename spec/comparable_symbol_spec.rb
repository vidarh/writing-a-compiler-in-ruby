require_relative '../rubyspec/spec_helper'

describe "Symbol comparison via Comparable" do
  it ":a < :b returns true" do
    (:a < :b).should == true
  end

  it ":b > :a returns true" do
    (:b > :a).should == true
  end

  it ":a <= :a returns true" do
    (:a <= :a).should == true
  end

  it ":a >= :a returns true" do
    (:a >= :a).should == true
  end

  it ":a == :a returns true" do
    (:a == :a).should == true
  end

  it ":a != :b returns true" do
    (:a != :b).should == true
  end

  it ":a.between?(:a, :z) returns true" do
    :a.between?(:a, :z).should == true
  end

  it ":z.between?(:a, :m) returns false" do
    :z.between?(:a, :m).should == false
  end
end

describe "Symbol comparison edge cases" do
  it "Symbol == comes from Comparable" do
    (:a == :a).should == true
  end

  it "Symbol compared to non-symbol returns nil" do
    (:a < "a").should == nil
  end
end
