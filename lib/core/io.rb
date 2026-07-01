
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

  def to_i
    @fd
  end

  def getc
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
