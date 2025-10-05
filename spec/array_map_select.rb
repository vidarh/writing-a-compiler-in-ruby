require_relative 'compilation_helper'

RSpec.describe "Array#map and Array#select" do
  include CompilationHelper

  it "supports Array#map as alias for collect" do
    code = <<-CODE
def test
  arr = [1, 2, 3, 4, 5]
  result = arr.map { |x| x * 2 }
  result.each { |x| puts x }
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("2\n4\n6\n8\n10")
  end

  it "supports Array#select to filter by block" do
    code = <<-CODE
def test
  arr = [1, 2, 3, 4, 5]
  result = arr.select { |x| x > 2 }
  result.each { |x| puts x }
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("3\n4\n5")
  end

  it "supports Array#select with all false returning empty array" do
    code = <<-CODE
def test
  arr = [1, 2, 3]
  result = arr.select { |x| x > 10 }
  puts result.length
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("0")
  end

  it "supports Array#select with all true returning full array" do
    code = <<-CODE
def test
  arr = [1, 2, 3]
  result = arr.select { |x| x > 0 }
  puts result.length
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("3")
  end

  it "handles map without block" do
    code = <<-CODE
def test
  arr = [1, 2, 3]
  result = arr.map
  puts result.length
end

test
CODE

    output = compile_and_run(code)
    expect(output).to eq("3")
  end
end
