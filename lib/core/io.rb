
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
end

class IOError
end

class IOSpecs
end
