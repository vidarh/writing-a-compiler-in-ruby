require_relative 'compilation_helper'

RSpec.describe "Array#collect with block" do
  include CompilationHelper

  it "compiles collect with block" do
    code = <<-RUBY
      arr = [1, 2, 3]
      result = arr.collect {|a| a * 2 }
      puts result.inspect
    RUBY

    output = compile_and_run(code, "-I.")
    expect(output).to eq("[2, 4, 6]")
  end
end
