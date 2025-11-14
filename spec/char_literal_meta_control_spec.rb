require_relative '../rubyspec/spec_helper'

# Character literal with \M- (meta) and \C- (control) escape sequences
# See: rubyspec/language/string_spec.rb:178
# Error: "Missing value in expression / op: {-/2 pri=14}"

describe "Character literal escape sequences" do
  it "handles \\M- meta escape" do
    ?\M-z.should == 250  # 0xFA
  end

  it "handles \\M-\\C- meta-control escape" do
    ?\M-\C-z.should == 154  # 0x9A
  end
end
