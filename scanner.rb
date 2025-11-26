

# The purpose of the Scanner is to present a narrow interface to read characters from, with support for lookahead / unget.
# Why not StringScanner? Well, it's a Ruby C-extension, and I want to get the compiler self-hosted as soon as possible,
# so I'm sticking to something simple. The code below is sufficient to write recursive descent parsers in a pretty
# concise style in Ruby
class Scanner
  attr_reader :col, :lineno, :filename # @filename holds the name of the file the parser reads from
  attr_reader :last_ws_consumed_newline # Tracks if the last ws() call consumed a newline
  attr_reader :had_ws_before_token # Tracks if whitespace was consumed before the current token

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

  # Set the parser position from a Position object (for backtracking)
  def position=(pos)
    @filename = pos.filename
    @lineno = pos.lineno
    @col = pos.col
  end

  def initialize(io)
    @io = io
    @buf = ""
    @lineno = 1
    @col = 1
    @last_ws_consumed_newline = false
    @had_ws_before_token = false

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
  # Note: semicolon removed from WS - it's an operator
  WS = [9,10,13,32,?#.ord]
  C = ?#
  # ws ::= ([\t\b\r ] | '#' [~\n]* '\n' | '\\' '\n')*
  def ws
    @last_ws_consumed_newline = false
    @had_ws_before_token = false
    while (c = peek) && (WS.member?(c.ord) || c == "\\")
      if c == "\\"
        # Check if it's line continuation: backslash followed by newline
        get
        if peek == LF
          get  # consume the newline
          @last_ws_consumed_newline = true
          @had_ws_before_token = true
        else
          # Not line continuation, put the backslash back
          unget("\\")
          break
        end
      else
        get
        @had_ws_before_token = true  # Track that whitespace was consumed
        @last_ws_consumed_newline = true if c.ord == 10  # Track newline consumption
        if c == C
          while (c = get) && c != LF do; end
          @last_ws_consumed_newline = true  # Comments end with newline
        end
      end
    end
  end

  # nolfws ::= [\t\r ]*
  NOLFWS = [9,13,32]

  def nolfws
    @had_ws_before_token = false
    had_any = false
    while (c = peek) && NOLFWS.member?(c.ord)
      get
      had_any = true
    end
    # Check if we stopped at a newline that's followed by . (method chaining)
    # If so, skip the newline and continue as if it were whitespace
    if peek == LF && peek_past_newline_is_dot?
      get  # consume the newline
      had_any = true
      nolfws  # recursively skip more whitespace
    end
    @had_ws_before_token = had_any
  end

  # Helper: Check if there's a . at the start of the next line (after newline + spaces)
  def peek_past_newline_is_dot?
    return false unless peek == LF

    # Save state
    saved_pos = @position
    saved_lineno = @lineno
    saved_col = @col

    # Collect characters we consume
    consumed = []

    consumed << get  # consume newline

    # Skip horizontal whitespace only
    while (c = peek) && [9, 32].member?(c.ord)
      consumed << get
    end

    # Check for .
    result = (peek == ?.)

    # Restore position by ungetting in reverse
    consumed.reverse.each { |ch| unget(ch) }
    @lineno = saved_lineno
    @col = saved_col

    result
  end
end
