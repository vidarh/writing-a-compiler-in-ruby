require_relative '../rubyspec/spec_helper'

# Endless ranges - Ruby 2.6+ feature
# See: rubyspec/language/range_spec.rb:56
# Error: "Missing value in expression / op: {assign/2 pri=7} / vstack: [] / rightv: [:range, :r, 1]"

describe "Endless ranges" do
  it "creates an endless range with .." do
    r = (1..)
    r.begin.should == 1
    r.end.should == nil
  end

  it "creates an endless exclusive range with ..." do
    r = (1...)
    r.begin.should == 1
    r.end.should == nil
  end
end
