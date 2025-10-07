require 'scanner'
require 'parserbase'
require 'parser'

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

prog = mock_parse('def foo; yield; end')
puts "prog = #{prog.inspect}"
