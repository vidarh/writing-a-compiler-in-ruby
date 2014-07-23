

# The purpose of the Scanner is to present a narrow interface to read characters from, with support for lookahead / unget.
# Why not StringScanner? Well, it's a Ruby C-extension, and I want to get the compiler self-hosted as soon as possible,
# so I'm sticking to something simple. The code below is sufficient to write recursive descent parsers in a pretty
# concise style in Ruby
class Scanner
  attr_reader :col, :lineno, :filename # @filename holds the name of the file the parser reads from

  Position = Struct.new(:filename, :lineno, :col)

  class Position
    def inspect
      "line #{self.lineno}, col #{self.col} in #{self.filename}"
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
      c = @io.getc
      c = c.chr if c
      @buf = c ? c.to_s : ""
    end
  end

  def peek
    fill
    return @buf[-1]
  end

  def get
    fill
    pos = position
    ch = @buf.slice!(-1,1)
    @col += 1
    if ch == "\n"
      @lineno += 1
      @col = 1
    end
    return nil if !ch
    s = ScannerString.new(ch)
    s.position = pos
    return s
  end

  def unget(c)
    if c.is_a?(String)
      c = c.reverse
      @col -= c.length
      ten = 10 # FIXME: This is a temporary hack to get the compiler linking
      @lineno -= c.count(ten.chr)
    else
      @col -= 1
    end
    if c.respond_to?(:position) and pos = c.position
      @lineno = pos.lineno
      @filename = pos.filename
      @col = pos.filename
    else
      #STDERR.puts "unget without position: #{c}"
    end
    @buf += c
  end
  
  # If &block is passed, it is a callback to parse an expression
  # that will be passed on to the method.
  def expect(str,&block)
    return buf if str == ""
    return str.expect(self,&block) if str.respond_to?(:expect)

    str = str.to_s
    buf = ScannerString.new
    buf.position = self.position
    str.each_byte do |s|
      c = peek
      if !c || c.chr.ord != s
        unget(buf) if !buf.empty?
        return false
      end
      buf << get
    end

    return buf
  end

  # ws ::= ([\t\b\r ] | '#' [~\n]* '\n')*
  def ws
    while (c = peek) && [9,10,13,32,?#.ord,?;.ord].member?(c.ord) do
      get
      if c == ?#
        while (c = get) && c != "\n" do; end
      end
    end
  end

  # nolfws ::= [\t\r ]*
  def nolfws
    while (c = peek) && [9, 13, 32].member?(c.ord) do get; end
  end
end
