require_relative '../rubyspec/spec_helper'

describe "While with parenthesized break" do
  it "handles break if inside parentheses" do
    a = [1, 2, 3]
    c = false
    x = a[0] ||= while a.shift
      (
        break if c
        c = false
      )
    end
    x.should be_nil
  end
end
