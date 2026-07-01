
# FIXME: This code is quite inefficient because we don't
# have an easy way of getting the address of a stack allocated
# variable (yet). Oh, and it leaks memory since we don't
# GC yet.


class IO < Object
  def initialize fd
    @fd = fd

    %s(assign tmp (__alloc_leaf 256))
    @rawbuf = tmp
  end

  # IO.sysopen(name, mode="r") -> the raw file descriptor (a tagged Integer, so it round-trips through
  # IO.new/#fileno). Mode may carry an :encoding suffix, ignored by File.__mode_to_flags. 420 = 0644.
  def self.sysopen(name, mode = "r")
    name = name.to_s
    flags = File.__mode_to_flags(mode)
    fd = -1
    %s(assign fd (__int (open (callm name __get_raw) (callm flags __get_raw) 420)))
    raise Errno::ENOENT.new("No such file or directory - #{name}") if fd < 0
    fd
  end

  # IO.for_fd(fd, *) / IO.open(fd) -> wrap an existing fd in an IO (opts ignored).
  def self.for_fd(fd, *opts)
    new(fd)
  end

  def to_i
    @fd
  end

  def getc
    if @pushback
      b = @pushback
      @pushback = nil
      return b
    end
    c = 0
    tmp = 0
    len = nil
    %s(do
         (assign len (read (callm @fd __get_raw) @rawbuf 1))
         (if (le len 0) (return nil))
         (assign c (__int (bindex @rawbuf 0)))
         )
    c
  end

  def file?
    false
  end

  # getbyte: like getc here (getc returns the next byte as an Integer, or nil at EOF).
  def getbyte
    getc
  end

  # gets(sep="\n"): read one line up to and including the separator byte (default newline), or nil at EOF.
  def gets(sep = "\n")
    line = ""
    got = false
    while (b = getc)
      got = true
      line = line + b.chr
      break if b == 10
    end
    return nil if !got
    line
  end

  def readline(sep = "\n")
    line = gets(sep)
    raise EOFError.new("end of file reached") if line.nil?
    line
  end

  def each_line(sep = "\n")
    return to_enum(:each_line) if !block_given?
    while (line = gets(sep))
      yield line
    end
    self
  end

  def each(sep = "\n")
    return to_enum(:each) if !block_given?
    while (line = gets(sep))
      yield line
    end
    self
  end

  def readlines(sep = "\n")
    result = []
    while (line = gets(sep))
      result << line
    end
    result
  end

  def each_byte
    return to_enum(:each_byte) if !block_given?
    while (b = getc)
      yield b
    end
    self
  end

  def each_char
    return to_enum(:each_char) if !block_given?
    while (b = getc)
      yield b.chr
    end
    self
  end

  # each_codepoint yields Integer codepoints. Byte-oriented here (no multibyte decoding).
  def each_codepoint
    return to_enum(:each_codepoint) if !block_given?
    while (b = getc)
      yield b
    end
    self
  end

  # read(length=nil): with no length, read to EOF and return a String (possibly ""). With a length, read
  # up to that many bytes and return a String, or nil once at EOF.
  def read(length = nil)
    if length
      s = ""
      n = 0
      while n < length && (b = getc)
        s = s + b.chr
        n = n + 1
      end
      return nil if s.length == 0 && length > 0
      return s
    end
    s = ""
    while (b = getc)
      s = s + b.chr
    end
    s
  end

  def eof?
    b = getc
    return true if b.nil?
    ungetc(b)
    false
  end

  def eof
    eof?
  end

  # ungetc: push a single byte back so the next getc returns it. Backed by a one-slot pushback buffer.
  def ungetc(c)
    @pushback = c.is_a?(String) ? c[0] : c
    nil
  end

  # Close the underlying fd (idempotent). @fd is a tagged Integer; __get_raw untags to the raw fd.
  def close
    return nil if @closed
    %s(close (callm @fd __get_raw))
    @closed = true
    nil
  end

  def closed?
    @closed == true
  end

  def fileno
    @fd
  end

  def to_io
    self
  end

  # Buffering / sync flags: tracked but not acted on (writes here are unbuffered already).
  def sync
    @sync == true
  end

  def sync=(v)
    @sync = v
    v
  end

  # autoclose defaults to true; only becomes false when explicitly set.
  def autoclose?
    @autoclose != false
  end

  def autoclose=(v)
    @autoclose = v
    v
  end

  def binmode
    @binmode = true
    self
  end

  def binmode?
    @binmode == true
  end

  # advise(advice, offset=0, len=0): posix_fadvise hint -- advisory only, so a no-op is a valid impl.
  def advise(advice, offset = 0, len = 0)
    nil
  end

  def flush
    self
  end

  def fsync
    0
  end

  def fdatasync
    0
  end
end

class IOError
end

# EOFError < IOError in MRI; defined here so IOError (above) is already in scope.
class EOFError < IOError
end

class IOSpecs
end
