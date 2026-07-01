# In-memory IO backed by a String buffer. Enough of the interface for the common uses: output capture
# ($stdout = StringIO.new; ...; io.string) and simple sequential reads.
class StringIO
  attr_accessor :string

  def initialize(string = "", mode = nil)
    @string = string.to_s
    @pos = 0
    @closed = false
  end

  def self.open(string = "", mode = nil)
    io = new(string, mode)
    if block_given?
      begin
        yield io
      ensure
        io.close
      end
    else
      io
    end
  end

  def string=(s)
    @string = s.to_s
    @pos = 0
    @string
  end

  def to_s
    @string
  end

  def pos
    @pos
  end
  alias tell pos

  def pos=(n)
    @pos = n
    n
  end

  def rewind
    @pos = 0
    0
  end

  def seek(amount, whence = 0)
    if whence == 1        # IO::SEEK_CUR
      @pos = @pos + amount
    elsif whence == 2     # IO::SEEK_END
      @pos = @string.length + amount
    else                  # IO::SEEK_SET
      @pos = amount
    end
    0
  end

  def size
    @string.length
  end
  alias length size

  def eof?
    @pos >= @string.length
  end
  alias eof eof?

  def close
    @closed = true
    nil
  end

  def closed?
    @closed
  end

  # --- writing ---

  # Write s's characters starting at @pos, overwriting/extending the buffer, and advance @pos.
  def __write_str(s)
    n = s.length
    len = @string.length
    if @pos >= len
      @string = @string + ("\0" * (@pos - len)) + s
    else
      before = @string[0...@pos]
      tail_start = @pos + n
      after = tail_start < @string.length ? @string[tail_start..-1] : ""
      @string = before + s + after
    end
    @pos = @pos + n
    n
  end

  def write(*args)
    total = 0
    args.each do |a|
      total = total + __write_str(a.to_s)
    end
    total
  end

  def <<(obj)
    __write_str(obj.to_s)
    self
  end

  def print(*args)
    args.each { |a| __write_str(a.to_s) }
    nil
  end

  def printf(fmt, *args)
    __write_str(sprintf(fmt, *args))
    nil
  end

  def puts(*args)
    if args.empty?
      __write_str("\n")
    else
      args.each do |a|
        if a.is_a?(Array)
          puts(*a)
        else
          s = a.to_s
          __write_str(s)
          __write_str("\n") if s.empty? || s[s.length - 1] != 10
        end
      end
    end
    nil
  end

  def putc(ch)
    if ch.is_a?(Integer)
      __write_str(ch.chr)
    else
      s = ch.to_s
      __write_str(s[0].chr) if s.length > 0
    end
    ch
  end

  # --- reading ---

  def read(length = nil)
    len = @string.length
    if @pos >= len
      return length ? nil : ""
    end
    if length.nil?
      r = @string[@pos..-1]
      @pos = len
      r
    else
      last = @pos + length
      last = len if last > len
      r = @string[@pos...last]
      @pos = last
      r
    end
  end

  def getc
    return nil if @pos >= @string.length
    c = @string[@pos].chr
    @pos = @pos + 1
    c
  end

  def gets(sep = "\n")
    return nil if @pos >= @string.length
    idx = @string.index(sep, @pos)
    if idx
      line = @string[@pos..idx]
      @pos = idx + sep.length
    else
      line = @string[@pos..-1]
      @pos = @string.length
    end
    line
  end

  def readline(sep = "\n")
    line = gets(sep)
    raise EOFError.new("end of file reached") if line.nil?
    line
  end

  def each_line(sep = "\n")
    while (line = gets(sep))
      yield line
    end
    self
  end
  alias each each_line

  def readlines(sep = "\n")
    lines = []
    while (line = gets(sep))
      lines << line
    end
    lines
  end

  def flush
    self
  end

  def sync
    true
  end

  def sync=(v)
    v
  end

  def fileno
    nil
  end
end
