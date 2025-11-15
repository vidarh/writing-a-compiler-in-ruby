require_relative '../rubyspec_helper'

# Hash spread operator ** (kwsplat)
# See: rubyspec/language/hash_spec.rb:161
# Error: "Missing value in expression / op: {**/2 pri=21}"

describe "Hash spread operator" do
  it "expands **hash into containing hash literal" do
    h = {b: 2, c: 3}
    {**h, a: 1}.should == {b: 2, c: 3, a: 1}
  end

  it "allows multiple spreads in one hash" do
    h1 = {a: 1}
    h2 = {b: 2}
    {**h1, **h2, c: 3}.should == {a: 1, b: 2, c: 3}
  end

  it "later values override earlier spreads" do
    h = {a: 1, b: 2}
    {**h, b: 99}.should == {a: 1, b: 99}
  end
end
