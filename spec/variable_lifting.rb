require_relative 'compilation_helper'

RSpec.describe "Variable lifting in blocks" do
  include CompilationHelper

  it "captures outer variable in block passed to method" do
    code = <<-RUBY
      def test_block
        pivot = 10
        [1, 5, 15, 20].each do |e|
          if e < pivot
            puts e
          end
        end
      end
      test_block
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("1\n5")
  end

  it "captures outer variable in partition block" do
    code = <<-RUBY
      def test_partition
        pivot = 10
        part = [1, 5, 15, 20].partition do |e|
          e < pivot
        end
        puts part[0].length
        puts part[1].length
      end
      test_partition
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("2\n2")
  end

  it "captures multiple outer variables in block" do
    code = <<-RUBY
      def test_multiple
        x = 5
        y = 10
        [1, 2, 3].each do |n|
          sum = n + x + y
          puts sum
        end
      end
      test_multiple
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("16\n17\n18")
  end

  it "captures variable in nested blocks" do
    code = <<-RUBY
      def test_nested
        outer = 100
        [[1, 2], [3, 4]].each do |arr|
          arr.each do |n|
            puts n + outer
          end
        end
      end
      test_nested
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("101\n102\n103\n104")
  end
end
