require_relative '../rubyspec/spec_helper'

describe "Hash spread operator (**)" do
  it "merges hash with ** operator" do
    h = {b: 2, c: 3}
    {**h, a: 1}.should == {b: 2, c: 3, a: 1}
  end

  it "spreads multiple hashes" do
    h1 = {a: 1}
    h2 = {b: 2}
    {**h1, **h2, c: 3}.should == {a: 1, b: 2, c: 3}
  end

  it "later values override earlier ones" do
    h = {a: 1, b: 2}
    {**h, b: 3}.should == {a: 1, b: 3}
  end
end
