require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/regexp/escapes_spec.rb
# Register allocator division by zero at regalloc.rb:332

describe "Regexp escapes" do
  it "handles escaped characters in regexes" do
    /\n/.should be_kind_of(Regexp)
  end
end
