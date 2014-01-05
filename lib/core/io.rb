
class IO < Object
  def initialize
#    %s(puts "IO.new")
  end

  def getc
    c = 0
    tmp = 0

    # FIXME: This code is specific to a 32 bit little endian
    # arch, and is also horribly inefficient because we don't
    # have an easy way of getting the address of a stack allocated
    # variable.
    %s(do
         (assign tmp (malloc 4))
         (assign (index tmp 0) 0)
         (read 0 tmp 1)
         (assign c (__get_fixnum (index tmp 0)))
         (free tmp)
         )
    c
  end

  def file?
  end

  def path
  end

end
