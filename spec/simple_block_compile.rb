require_relative 'compilation_helper'

RSpec.describe "Simple block compilation" do
  include CompilationHelper

  it "compiles simple collect block" do
    code = <<-RUBY
      result = [1,2,3].collect {|x| x}
      puts result.inspect
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("[1, 2, 3]")
  end
end
