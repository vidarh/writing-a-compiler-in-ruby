require_relative 'spec_helper'
require_relative 'compilation_helper'

describe "Character Literals" do
  include CompilationHelper

  it "should support regular character literal ?n" do
    code = <<-CODE
puts ?n.ord
CODE
    output = compile_and_run(code)
    output.should == "110"
  end

  it "should support ?\\e escape character literal" do
    code = <<-CODE
puts ?\e.ord
CODE
    output = compile_and_run(code)
    output.should == "27"
  end

  it "should support ?\\t tab character literal" do
    code = 'puts ?\t.ord'
    output = compile_and_run(code)
    output.should == "9"
  end

  it "should support regular character literals" do
    code = <<-CODE
puts ?A.ord
CODE
    output = compile_and_run(code)
    output.should == "65"
  end

  it "should support ?\\n newline character literal" do
    code = 'puts ?\n.ord'
    output = compile_and_run(code)
    output.should == "10"
  end
end