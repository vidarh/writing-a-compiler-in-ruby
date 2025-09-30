require_relative 'spec_helper'
require_relative 'compilation_helper'

describe "Instance Variables" do
  include CompilationHelper

  it "should return nil for uninitialized instance variables" do
    code = <<-CODE
class TestIvar
  def initialize
    # Don't initialize @uninitialized
  end

  def get_uninitialized
    @uninitialized
  end

  def check_if_zero
    if @uninitialized == 0
      puts "BUG: ivar is 0"
    elsif @uninitialized == nil
      puts "GOOD: ivar is nil"
    else
      puts "UNEXPECTED: ivar is " + @uninitialized.inspect
    end
  end
end

obj = TestIvar.new
result = obj.get_uninitialized
puts result.inspect
obj.check_if_zero
CODE

    output = compile_and_run(code)

    # Expected output should include "nil" and "GOOD: ivar is nil"
    # If bug exists, will show "BUG: ivar is 0"
    output.should include("nil")
    output.should include("GOOD: ivar is nil")
    output.should_not include("BUG: ivar is 0")
  end
end