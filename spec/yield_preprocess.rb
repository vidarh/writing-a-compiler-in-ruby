require_relative 'compilation_helper'

RSpec.describe "Yield preprocessing" do
  include CompilationHelper

  it "preprocesses yield in method" do
    code = <<-RUBY
      def foo
        yield
      end
      puts "ok"
    RUBY

    output = compile_and_run(code)
    expect(output).to eq("ok")
  end
end
