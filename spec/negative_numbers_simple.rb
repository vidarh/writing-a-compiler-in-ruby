require_relative 'compilation_helper'

RSpec.describe "Negative numbers (simple)" do
  include CompilationHelper

  it "handles unary minus with parentheses" do
    code = <<-RUBY
      def negate(x)
        (-x)
      end
      puts negate(5)
      puts negate(10)
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("-5\n-10")
  end

  it "handles unary minus in expression" do
    code = <<-RUBY
      x = 5
      y = -x
      puts y
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("-5")
  end

  it "handles double negation" do
    code = <<-RUBY
      x = 5
      y = -(-x)
      puts y
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("5")
  end
end