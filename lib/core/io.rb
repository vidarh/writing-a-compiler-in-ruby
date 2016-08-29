
# FIXME: This code is quite inefficient because we don't
# have an easy way of getting the address of a stack allocated
# variable (yet). Oh, and it leaks memory since we don't
# GC yet.


class IO < Object
  def initialize fd
    @fd = fd

    %s(assign tmp (malloc 256))
    @rawbuf = tmp
  end

  def getc
    c = 0
    tmp = 0

    %s(do
         (read (callm @fd __get_raw) @rawbuf 1)
         (assign c (__get_fixnum (bindex @rawbuf 0)))
         )
    c
  end

  def file?
    false
  end

  def path
  end

end
