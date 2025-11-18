require_relative '../rubyspec/spec_helper'

describe "Splat with begin...end in array indexing brackets" do
  it "works with splat in brackets without begin...end" do
    h = {a: 1}
    x = h[*[:a]]
    x.should == 1
  end

  it "works with begin...end in brackets without splat" do
    h = {a: 1}
    x = h[begin :a end]
    x.should == 1
  end

  it "works with splat and parentheses in brackets" do
    h = {a: 1}
    x = h[*([:a])]
    x.should == 1
  end

  it "works with splat+begin...end in method calls" do
    def foo(*args)
      args
    end
    result = foo(*begin [:a, :b] end)
    result.should == [:a, :b]
  end

  # FAILS: Syntax error. [{array/1 pri=97}]
  # The parser leaves an unclosed [ on the operator stack when
  # combining splat operator with begin...end block inside array
  # indexing brackets. The array literal inside the begin block
  # causes confusion about which [ context we're in.
  xit "should work with splat+begin...end in brackets" do
    h = {a: 1}
    x = h[*begin [:a] end]
    x.should == 1
  end
end
