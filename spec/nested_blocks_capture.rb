require_relative 'compilation_helper'

RSpec.describe "Nested blocks with outer variable capture" do
  include CompilationHelper

  it "captures outer block variable in nested block" do
    code = <<-RUBY
      def test
        result = []
        [[1, 2], [3, 4]].each do |outer|
          outer.each_with_index do |val, i|
            result << outer[i]
          end
        end
        result.each {|x| puts x }
      end
      test
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("1\n2\n3\n4\n")
  end

  it "captures and modifies outer block variable in nested iteration" do
    code = <<-RUBY
      def test
        arrays = [[1, 2], [3, 4]]
        arrays.each do |arr|
          arr.each_with_index do |val, i|
            arr[i] = val * 2
          end
        end
        arrays.each do |arr|
          arr.each {|x| puts x }
        end
      end
      test
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("2\n4\n6\n8\n")
  end
end
