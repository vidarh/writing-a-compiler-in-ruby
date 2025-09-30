require_relative 'spec_helper'
require_relative 'compilation_helper'

describe "Global Variables" do
  include CompilationHelper

  it "should support basic global variable assignment and retrieval" do
    code = <<-CODE
$global_var = 42
puts $global_var
CODE

    output = compile_and_run(code)
    output.should == "42"
  end

  it "should maintain global variable state across method calls" do
    code = <<-CODE
$counter = 0

def increment
  $counter = $counter + 1
end

def get_counter
  $counter
end

increment
increment
increment
puts get_counter
CODE

    output = compile_and_run(code)
    output.should == "3"
  end

  it "should initialize undefined globals to nil" do
    code = <<-CODE
if $undefined_global == nil
  puts "nil"
else
  puts "not nil: " + $undefined_global.inspect
end
CODE

    output = compile_and_run(code)
    output.should include("nil")
  end
end