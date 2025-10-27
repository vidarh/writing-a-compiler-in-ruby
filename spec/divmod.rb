require 'compilation_helper'

RSpec.describe "Integer#divmod" do
  include CompilationHelper

  it "returns correct quotient and remainder for fixnum division" do
    code = <<~RUBY
      result = 10.divmod(3)
      puts result[0]
      puts result[1]
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("3\n1")
  end

  it "returns correct quotient and remainder for zero remainder" do
    code = <<~RUBY
      result = 10.divmod(5)
      puts result[0]
      puts result[1]
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("2\n0")
  end

  it "returns correct quotient and remainder for negative dividend" do
    code = <<~RUBY
      result = (-10).divmod(3)
      puts result[0]
      puts result[1]
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("-4\n2")
  end

  it "returns correct quotient and remainder for negative divisor" do
    code = <<~RUBY
      result = 10.divmod(-3)
      puts result[0]
      puts result[1]
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("-4\n-2")
  end

  it "returns correct quotient and remainder for both negative" do
    code = <<~RUBY
      result = (-10).divmod(-3)
      puts result[0]
      puts result[1]
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("3\n-1")
  end

  it "raises ZeroDivisionError when dividing by zero" do
    code = <<~RUBY
      begin
        10.divmod(0)
        puts "NO_ERROR"
      rescue ZeroDivisionError
        puts "ZERO_ERROR"
      end
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("ZERO_ERROR")
  end

  it "raises TypeError when given non-numeric argument" do
    code = <<~RUBY
      begin
        10.divmod("hello")
        puts "NO_ERROR"
      rescue TypeError
        puts "TYPE_ERROR"
      end
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("TYPE_ERROR")
  end
end
