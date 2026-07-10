

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

  # Return the current position of the parser in one convenient object. Cached: position() is queried
  # repeatedly at the same spot (peek/get/parser all ask), and Position is an immutable snapshot, so the
  # same object can be shared until line/col/file actually change.
  def position
    if @pos_cache && @pos_col == @col && @pos_lineno == @lineno && @pos_fn == @filename
      return @pos_cache
    end
    @pos_col = @col; @pos_lineno = @lineno; @pos_fn = @filename
    @pos_cache = Position.new(@filename, @lineno, @col)
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
    @peeked = nil
    @pos_cache = nil
    @atom_off = nil
    @lineno = 1
    @col = 1
    @last_ws_consumed_newline = false
    @had_ws_before_token = false

    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, indicate it comes from a stream
    @filename = io.is_a?(File) && File.file?(io) ? File.expand_path(io.path) : "<stream>"

    # Read the whole input into an in-memory char array ONCE so `fill` indexes it, instead of
    # interleaving @io.getc with the @buf pushback-string churn on every scan. Semantics are
    # unchanged (the "HybridScanner" from docs/scanner-analysis): @pos is the next unread SOURCE
    # char; @buf still holds pushback for unget. Slurp via getc (the scanner's ONLY io contract --
    # not read/seek; io is often STDIN, and the unit tests pass a getc-only MockIO). Char array,
    # not String indexing, keeps @chars[@pos] O(1). Works identically MRI-hosted and self-hosted.
    @chars = []
    while c = io.getc
      # getc returns a fresh 1-char String for real IO -- store it directly (c.chr would copy it again).
      # Only a byte Integer (binary IO / getc-only MockIO) needs .chr to normalise to a 1-char String.
      @chars << (c.is_a?(String) ? c : c.chr)
    end
    # @chars is fully slurped here and never mutated afterwards, so cache its length once. fill (below)
    # runs once per source char and previously dispatched @chars.length every time.
    @nchars = @chars.length
    @pos = 0
  end

  def fill
    if @buf.empty?
      if @pos < @nchars
        @buf = @chars[@pos]
        @pos += 1
      end
    end
  end

  def peek
    fill
    # Cache the lookahead char: @buf[-1] allocates a fresh 1-char String every call, and peek is called
    # ~twice per source char -- the single biggest compile allocator. The cache is invalidated (set nil)
    # by every @buf mutation (get / get_ch / unget), so it re-allocates at most once per consumed char.
    @peeked = @buf[-1] if @peeked.nil?
    @peeked
  end

  LF="\n"

  def get
    fill
    pos = position
    ch = @buf.slice!(-1,1)
    @peeked = nil
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

  # Allocation-free variant of #get: returns the bare next character (a plain 1-char String) rather than
  # a ScannerString carrying a Position. For hot consume-and-discard loops (whitespace, comments) this
  # skips the per-char Position + ScannerString allocation -- the headline allocation win for the simple
  # GC (see docs/scanner-analysis). Same @col/@lineno bookkeeping as #get, so it interleaves safely with
  # #get/#peek/#unget (unget of a bare char restores lineno/col by its length, no Position needed).
  def get_ch
    fill
    ch = @buf.slice!(-1,1)
    @peeked = nil
    @col += 1
    if ch == LF
      @lineno += 1
      @col = 1
    end
    return nil if !ch
    ch
  end

  def unget(c)
    # reverse allocates a copy; a single-char unget (the common case -- bare-char pushback) needs no reverse.
    @buf << (c.length == 1 ? c : c.reverse)
    @peeked = nil
    @atom_off = nil

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

  # Peek the atom at the current position WITHOUT permanently consuming it, memoized by stream offset.
  # (Bisect experiment: single-return form; the reverted version used `return @atom_val if ...`.)
  def peek_atom
    off = @pos - @buf.length
    if @atom_off != off
      a = Tokens::Atom.expect(self)
      unget(a.to_s) if a
      @atom_off = off
      @atom_val = a
    end
    @atom_val
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
    while (c = peek) && ((o = c.ord) == 9 || o == 10 || o == 13 || o == 32 || o == 35 || o == 92)  # WS + '\\'
      if c == "\\"
        # Check if it's line continuation: backslash followed by newline
        get_ch
        if peek == LF
          get_ch  # consume the newline
          @last_ws_consumed_newline = true
          @had_ws_before_token = true
        else
          # Not line continuation, put the backslash back
          unget("\\")
          break
        end
      else
        get_ch
        @had_ws_before_token = true  # Track that whitespace was consumed
        @last_ws_consumed_newline = true if c.ord == 10  # Track newline consumption
        if c == C
          while (c = get_ch) && c != LF do; end
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
    while (c = peek) && ((o = c.ord) == 9 || o == 13 || o == 32)   # NOLFWS
      get_ch
      had_any = true
    end
    # Backslash line continuation: a "\" immediately followed by a newline joins the next line, so it
    # must be consumed here too (ws consumes it, but after a value the tokenizer uses nolfws). This is
    # lexical, not grammar -- the backslash+newline is simply not a token.
    if peek == "\\"
      bs = get_ch
      if peek == LF
        get_ch  # consume the newline
        had_any = true
        nolfws  # continue scanning whitespace on the joined line
        @had_ws_before_token = had_any
        return
      end
      unget(bs)  # not a continuation -- put the backslash back (bare char; unget restores by length)
    end
    # Check if we stopped at a newline that's followed by . (method chaining)
    # If so, skip the newline and continue as if it were whitespace
    if peek == LF && peek_past_newline_is_dot?
      get_ch  # consume the newline
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
    while (c = peek) && ((o = c.ord) == 9 || o == 32)   # [9,32].member? allocated an Array per char
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
