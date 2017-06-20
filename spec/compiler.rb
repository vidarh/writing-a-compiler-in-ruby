
require_relative '../compiler'

describe Compiler do

  describe "#clean_method_name" do

    it "should escape all characters outside [a-zA-Z0-9_]" do
      input = (0..255).to_a.pack("c*")
      output = Compiler.new.clean_method_name(input)
      expect(output.match("([0-9a-zA-Z_])+")[0]).to eq(output)
    end

  end
end
