
# The purpose of the Scanner is to present a narrow interface to read characters from, with support for lookahead / unget.
# Why not StringScanner? Well, it's a Ruby C-extension, and I want to get the compiler self-hosted as soon as possible,
# so I'm sticking to something simple. The code below is sufficient to write recursive descent parsers in a pretty
# concise style in Ruby
class Scanner
  attr_reader :col,:lineno, :filename # @filename holds the name of the file the parser reads from

  def initialize(io)
    @io = io
    @buf = ""
    @lineno = 1
    @col = 1

    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, simply set it to nil
    @filename = File.file?(io) and io.is_a?(File) ? io.path : nil
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
    ch = @buf.slice!(-1,1)
    @col += 1
    if ch == "\n"
      @lineno += 1
      @col = 1
    end
    return ch
  end

  def unget(c)
    if c.is_a?(String)
      c = c.reverse
      @col -= c.length
    else
      @col -= 1
    end
    @buf += c
    # FIXME: Count any linefeeds too.
  end

  def expect(str)
    return buf if str == ""
    return str.expect(self) if str.respond_to?(:expect)
    buf = ""
    str.each_byte do |s|
      c = peek
      if !c || c.to_i != s
        unget(buf) if !buf.empty?
        return false
      end
      buf += get
    end
    return buf
  end

  # ws ::= ([\t\b\r ] | '#' [~\n]* '\n')*
  def ws
    while (c = peek) && [9,10,13,32,?#].member?(c) do
      get
      if c == ?#
        while (c = get) && c != "\n" do end
      end
    end
  end

  # nolfws ::= [\t\r ]*
  def nolfws
    while (c = peek) && [9, 13, 32].member?(c) do get; end
  end
end
