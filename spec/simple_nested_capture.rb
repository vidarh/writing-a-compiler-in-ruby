require_relative 'compilation_helper'

RSpec.describe "Simple nested block capture" do
  include CompilationHelper

  it "captures outer each variable in nested each" do
    code = <<-RUBY
      def test
        [[1, 2]].each do |arr|
          arr.each {|x| puts x }
        end
      end
      test
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("1\n2")
  end

  it "captures outer each variable reference in nested each" do
    code = <<-RUBY
      def test
        [[1]].each do |arr|
          arr.each {|x| puts arr.length }
        end
      end
      test
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("1")
  end

  it "captures outer each_with_index variable in nested each" do
    code = <<-RUBY
      def test
        [[5, 6]].each_with_index do |arr, i|
          arr.each {|x| puts i }
        end
      end
      test
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("0\n0")
  end
end
