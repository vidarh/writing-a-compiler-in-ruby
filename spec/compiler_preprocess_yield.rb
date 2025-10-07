require_relative 'compilation_helper'

RSpec.describe "Compiler preprocess with yield" do
  include CompilationHelper

  it "preprocesses yield correctly" do
    code = <<-'RUBY'
require 'scanner'
require 'parserbase'  
require 'parser'
require 'emitter'
require 'compiler'

class MockIO
  def initialize str
    @str = str
    @pos = 0
  end

  def getc
    if @pos < @str.size
      c = @str[@pos]
      @pos = @pos + 1
      c
    else
      nil
    end
  end
end

def mock_scanner(str)
  io = MockIO.new(str)
  Scanner.new(io)
end

def mock_parse(str)
  parser = Parser.new(mock_scanner(str))
  parser.parse(false)
end

def test_compiler
  e = Emitter.new
  c = Compiler.new(e)
  prog = mock_parse('
def foo
  yield
end
')
  c.preprocess(prog)
  puts "ok"
end

test_compiler
    RUBY

    output = compile_and_run(code, "-I.")
    expect(output).to eq("ok")
  end
end
