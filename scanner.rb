

# The purpose of the Scanner is to present a narrow interface to read characters from, with support for lookahead / unget.
# Why not StringScanner? Well, it's a Ruby C-extension, and I want to get the compiler self-hosted as soon as possible,
# so I'm sticking to something simple. The code below is sufficient to write recursive descent parsers in a pretty
# concise style in Ruby
class Scanner
  attr_reader :col, :lineno, :filename # @filename holds the name of the file the parser reads from

#  Position = Struct.new(:filename, :lineno, :col)

  class Position
    def initialize(filename,lineno,col)
      @filename = filename
      @lineno   = lineno
      @col      = col
    end

    attr_accessor :filename, :lineno, :col

    def inspect
      # FIXME: If these are inlined, they are treated incorrectly.
      l = self.lineno
      c = self.col
      "line #{l}, col #{c} in #{self.filename}"
    end

    def short
      "#{File.basename(self.filename)}, @#{self.lineno},#{self.col}"
    end
  end

  class ScannerString < String
    attr_accessor :position
  end

  # Return the current position of the parser in one convenient object...
  def position
    Position.new(@filename,@lineno,@col)
  end

  def initialize(io)
    @io = io
    @buf = ""
    @lineno = 1
    @col = 1

    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, indicate it comes from a stream
    @filename = io.is_a?(File) && File.file?(io) ? File.expand_path(io.path) : "<stream>"
  end

  def fill
    if @buf.empty?
      if c = @io.getc
        @buf = c.chr
      end
    end
  end

  def peek
    fill
    return @buf[-1]
  end

  LF="\n"

  def get
    fill
    pos = position
    ch = @buf.slice!(-1,1)
    @col += 1
    if ch == LF
      @lineno += 1
      @col = 1
    end
    return nil if !ch
    s = ScannerString.new(ch)
    s.position = pos
    return s
  end

  def unget(c)
    @buf << c.reverse

    if c.respond_to?(:position)
      pos = c.position
      if pos
        @lineno = pos.lineno
        @filename = pos.filename
        @col = pos.col
        return
      end
    end

    if c.is_a?(String)
      @col -= c.length
      #ten = 10 # FIXME: This is a temporary hack to get the compiler linking
      #@lineno -= c.count(ten.chr)
      @lineno -= c.count(LF)
    else
      @col -= 1
    end
  end

  # If &block is passed, it is a callback to parse an expression
  # that will be passed on to the method.
  EMPTY=""
  def expect(str,&block)
    return buf if str == EMPTY
    return str.expect(self,&block) if str.respond_to?(:expect)
    expect_str(str,&block)
  end

  def expect_str(str, &block)
    str = str.to_s
    return false if peek != str[0]
    buf = ScannerString.new
    buf.position = self.position
    str.each_byte do |s|
      c = peek
      if !c || c.ord != s
        unget(buf) if !buf.empty?
        return false
      end
      buf << get
    end
    return buf
  end

  # Avoid initialization on every call. Hacky workaround.
  WS = [9,10,13,32,?#.ord,?;.ord]
  C = ?#
  # ws ::= ([\t\b\r ] | '#' [~\n]* '\n')*
  def ws
    while (c = peek) && WS.member?(c.ord) do
      get
      if c == C
        while (c = get) && c != LF do; end
      end
    end
  end

  # nolfws ::= [\t\r ]*
  NOLFWS = [9,13,32]

  def nolfws
    while (c = peek) && NOLFWS.member?(c.ord) do get; end
  end
end
