require_relative '../rubyspec/spec_helper'

# Reproduces: rubyspec/language/symbol_spec.rb line 91
# Expression did not reduce to single value (2 values on stack)
# Triggered by %w with quoted strings: %w{'!' '!=' '!~'}

describe "Symbol with %w and quotes" do
  it "handles %w with quoted special characters" do
    %w{'!', '!=', '!~'}.each do |sym|
      sym.should be_kind_of(String)
    end
  end
end
