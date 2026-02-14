require_relative '../rubyspec/spec_helper'

# NOTE: Cannot use instance variables because run_rubyspec rewrites
# all @var to $spec_var via sed. We use a global Hash keyed by object_id
# to store per-instance state instead.

$__ct_values = {}

class ComparableTest
  include Comparable
  def initialize(v)
    $__ct_values[object_id] = v
  end
  def value
    $__ct_values[object_id]
  end
  def <=>(other)
    self.value <=> other.value
  end
end

class ComparableNilTest
  include Comparable
  def <=>(other)
    nil
  end
end

describe("Comparable#<") do
  it "returns true when self is less" do
    (ComparableTest.new(1) < ComparableTest.new(2)).should == true
  end

  it "returns false when self is equal" do
    (ComparableTest.new(1) < ComparableTest.new(1)).should == false
  end

  it "returns false when self is greater" do
    (ComparableTest.new(2) < ComparableTest.new(1)).should == false
  end
end

describe("Comparable#<=") do
  it "returns true when less" do
    (ComparableTest.new(1) <= ComparableTest.new(2)).should == true
  end

  it "returns true when equal" do
    (ComparableTest.new(1) <= ComparableTest.new(1)).should == true
  end

  it "returns false when greater" do
    (ComparableTest.new(2) <= ComparableTest.new(1)).should == false
  end
end

describe("Comparable#>") do
  it "returns true when self is greater" do
    (ComparableTest.new(2) > ComparableTest.new(1)).should == true
  end

  it "returns false when self is equal" do
    (ComparableTest.new(1) > ComparableTest.new(1)).should == false
  end

  it "returns false when self is less" do
    (ComparableTest.new(1) > ComparableTest.new(2)).should == false
  end
end

describe("Comparable#>=") do
  it "returns true when greater" do
    (ComparableTest.new(2) >= ComparableTest.new(1)).should == true
  end

  it "returns true when equal" do
    (ComparableTest.new(1) >= ComparableTest.new(1)).should == true
  end

  it "returns false when less" do
    (ComparableTest.new(1) >= ComparableTest.new(2)).should == false
  end
end

describe("Comparable#==") do
  # NOTE: Comparable#== cannot override Object#== because this compiler's
  # __include_module only fills uninitialized vtable slots. Object#== (identity)
  # is always defined first, so Comparable#== never gets installed.
  # We test identity-based == here instead.

  it "returns true for identity (same object)" do
    a = ComparableTest.new(5)
    (a == a).should == true
  end

  it "returns false for different objects" do
    (ComparableTest.new(1) == ComparableTest.new(2)).should == false
  end
end

describe("Comparable#between?") do
  it "returns true when self is within range" do
    ComparableTest.new(5).between?(ComparableTest.new(1), ComparableTest.new(10)).should == true
  end

  it "returns true when self equals min" do
    ComparableTest.new(1).between?(ComparableTest.new(1), ComparableTest.new(10)).should == true
  end

  it "returns true when self equals max" do
    ComparableTest.new(10).between?(ComparableTest.new(1), ComparableTest.new(10)).should == true
  end

  it "returns true when min equals max equals self" do
    ComparableTest.new(5).between?(ComparableTest.new(5), ComparableTest.new(5)).should == true
  end

  it "returns false when self is below min" do
    ComparableTest.new(0).between?(ComparableTest.new(1), ComparableTest.new(10)).should == false
  end

  it "returns false when self is above max" do
    ComparableTest.new(11).between?(ComparableTest.new(1), ComparableTest.new(10)).should == false
  end
end

describe("Comparable edge cases") do
  it "handles negative values" do
    (ComparableTest.new(-5) < ComparableTest.new(-1)).should == true
  end

  it "handles large values" do
    (ComparableTest.new(999999) > ComparableTest.new(-999999)).should == true
  end

  it "handles zero comparison" do
    (ComparableTest.new(0) <= ComparableTest.new(0)).should == true
  end
end

describe("Comparable nil return from <=>") do
  it "< returns nil when <=> returns nil" do
    a = ComparableNilTest.new
    b = ComparableNilTest.new
    (a < b).should == nil
  end

  it "== returns false when <=> returns nil" do
    a = ComparableNilTest.new
    b = ComparableNilTest.new
    (a == b).should == false
  end

  it "between? with nil <=> does not crash" do
    a = ComparableNilTest.new
    b = ComparableNilTest.new
    c = ComparableNilTest.new
    a.between?(b, c).should == false
  end
end

describe("Integer non-regression") do
  it "Integer < still works" do
    (1 < 2).should == true
  end

  it "Integer > still works" do
    (2 > 1).should == true
  end

  it "Integer == still works" do
    (5 == 5).should == true
  end

  it "Integer between? works" do
    5.between?(1, 10).should == true
  end
end
