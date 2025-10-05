require_relative 'compilation_helper'

RSpec.describe "Yield inside block segfault bug" do
  include CompilationHelper

  it "should handle yield called from within a block passed to another method (inside method)" do
    # This tests the fix for yield-in-block when the lambda is created inside a method
    # The lambda receives the outer method's __closure__ via Proc#call
    code = <<-CODE
def outer
  inner { yield }
end

def inner
  yield
end

def main
  outer { puts "Hello" }
end

main
CODE

    output = compile_and_run(code)
    expect(output).to eq("Hello")
  end

  it "demonstrates the issue with map calling yield inside collect block (inside method)" do
    # This is the real-world case: Array#map calling yield inside collect block
    code = <<-CODE
class Array
  def map_broken
    collect { |item| yield(item) }
  end
end

def test
  arr = [1, 2]
  result = arr.map_broken { |x| x * 2 }
  puts result.length
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("2")
  end

  it "should handle yield in block at top-level (KNOWN BUG)" do
    # This documents a separate bug: lambdas created at top-level don't have __closure__ available
    # At top-level, __closure__ is not defined, so passing it to __new_proc fails
    code = <<-CODE
def outer
  inner { yield }
end

def inner
  yield
end

outer { puts "Hello" }
CODE

    # This currently fails due to top-level lambda bug (separate from yield-in-block fix)
    output = compile_and_run(code)
    expect(output).to eq("Hello")
  end
end
