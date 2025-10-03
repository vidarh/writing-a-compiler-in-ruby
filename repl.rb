
# Helpers to make it more convenient to experiment in pry.


$e = Emitter.new
$c = Compiler.new($e)

class MockIO
  def initialize str
    @str = str
    @pos = 0
  end


  def to_str
    @str
  end

  def getc
    ch = @str[@pos]
    @pos += 1
    ch
  end
end

def mock_scanner(str)
  io = MockIO.new(str)
  Scanner.new(io)
end

def parse(str, require_core = false)
  parser = Parser.new(mock_scanner(str))
  parser.parse(require_core)
end
