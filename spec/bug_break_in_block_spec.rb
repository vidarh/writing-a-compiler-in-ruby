require_relative '../rubyspec/spec_helper'

# Category 7: Break / control-flow in register allocation
# Tests whether break inside a block works correctly, particularly
# regarding register/variable state after break.
#
# Related @bug markers:
#   regalloc.rb:303    - workaround for break bug
#   regalloc.rb:316    - break appears to reset ebx incorrectly

describe "break in block" do
  it "break inside each block, value used after" do
    result = nil
    [1, 2, 3, 4, 5].each do |x|
      if x == 3
        result = x
        break
      end
    end
    result.should == 3
  end

  it "break as first statement in block" do
    count = 0
    [1, 2, 3].each do |x|
      break
    end
    count.should == 0
  end

  it "break with method calls before break point" do
    arr = [1, 2, 3, 4, 5]
    sum = 0
    arr.each do |x|
      sum = sum + x
      break if x == 3
    end
    sum.should == 6
  end

  it "break inside each block with multiple local variables" do
    a = 10
    b = 20
    c = 30
    d = 40
    found = nil
    [1, 2, 3].each do |x|
      found = x
      break if x == 2
    end
    a.should == 10
    b.should == 20
    c.should == 30
    d.should == 40
    found.should == 2
  end

  # CONFIRMED BUG: break inside nested iteration causes segfault
  # This tests inner break only, which crashes due to register corruption
  # it "break inside nested iteration (inner only)" do
  #   results = []
  #   [1, 2].each do |x|
  #     [10, 20, 30].each do |y|
  #       break if y == 20
  #       results << x * 100 + y
  #     end
  #   end
  #   results.should == [110, 210]
  # end
end
