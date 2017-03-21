
# See Symbol for a discussion of type tagging.
#
# FIXME: For (right) now String objects are sort-of immutable.
# At least #concat needs to be implemented for our needed
# use in #attr_writer.
class String
  # NOTE
  # Changing this to '= ""' is likely to fail, as it
  # gets translated into '__get_string("")', which
  # will do (callm String new), leading to a loop that
  # will only terminate when the stack blows up.
  #
  # Setting it "= <some other default>" may work, but
  # will be prone to order of bootstrapping the core
  # classes.
  #
  def initialize *str
    # @buffer contains the pointer to raw memory
    # used to contain the string.
    # 
    # An s-expression is used rather than = because
    # 0 outside of the s-expression eventually will
    # be an FixNum instance instead of the actual
    # value 0.

    %s(if (lt numargs 3)
         (assign @buffer "")
         (do 
            (assign first (callm str [] ((__get_fixnum 0))))
            (assign len (callm first length))
            (callm self __copy_raw ((callm first __get_raw) len))
          )
          )
  end

  def inspect
    "\""+self+"\""
  end

  # DJB hash
  def hash
    h = 5381
    each_byte do |c|
      h = h * 33 + c
    end
    h
  end

  def !
    false
  end

  def nil?
    false
  end


  def [] index
    l = length

    if index.is_a?(Range)
      b = index.first
      e = index.last

      if b < 0
        b = l + b
        if b < 0
          return nil
        end
      end

      if e < 0
        e = l + e + 1
        if e < 0
          e = 0
        end
      end

      if e > l
        e = l
      end
      e = e - b

      a = String.new
      %s(assign src (add @buffer (callm b __get_raw)))
      a.__copy_raw(src, e)
      return a
    end

    if index < 0
      index = l + index
      if index < 0
        return nil
      end
    end

    if index >= l
      return nil
    end
    %s(assign index (callm index __get_raw))
    %s(assign c (bindex @buffer index))
    %s(__get_fixnum c)
  end

  def == other
    s = other.is_a?(String)
    return false if !s
    %s(assign res (if (strcmp @buffer (callm other __get_raw)) false true))
    return res
  end

  def eql? other
    self.== other
  end

  def __copy_raw(str,len)
    %s(assign len (callm len __get_raw))
    %s(assign @buffer (malloc len))
    %s(memmove @buffer str len)
   end

  def __set_raw(str)
    @buffer = str
  end

  def __get_raw
    @buffer
  end

  def empty?
    # FIXME: horribly inefficient while length is calculated with strlen...
    length == 0
  end


  def chr
    self[0]
  end

  def ord
    # FIXME: On empty string we're obliged to throw an ArgumentError

    # FIXME: This is 1.8.x behaviour; for 1.9.x, String[] behaviur changes, and
    # we ned to change this accordingly.
    self[0]
  end

  def each_byte
    i = 0
    len = length
    while i <  len
      yield(self[i])
      i = i + 1
    end
    self
  end

  def uniq
  end

  def to_s
    self
  end

  def to_sym
    buffer = @buffer
    %s(call __get_symbol buffer)
  end

  def to_i
    i = 0
    each_byte do |s|
      return i if !(?0..?9).member?(s) 
      i = i*10 + s - ?0
    end
    i
  end

  def slice!(b,e)

    l = length
    # Negative offset?
    if b < 0
      b = l + b
    end
    
    if b < 0
      return nil
    end

    endp = b + e
    if endp > l
      e = l - b
    end

    n = String.new
    %s(assign src (add @buffer (callm b __get_raw)))
    n.__copy_raw(src, e)

    endp = b + e + 1
    %s(assign dest (add @buffer (callm b __get_raw)))
    %s(assign src (add @buffer (callm endp __get_raw)))
    %s(memmove dest src (callm e __get_raw))

    n
   end


  def reverse
    buf = ""
    l = length
    if l == 0
      return
    end
    while (l > 0)
      l = l - 1
      buf << self[l].chr
    end
    buf
  end

  def length
    # FIXME: yes, we should not assume C-strings
    # FIXME: Also, this is not nice if @buffer == -
    %s(assign l (strlen @buffer))
    %s(__get_fixnum l)
  end

  def size
    length
  end

  def count c = nil
    1
  end

  # FIXME: This is horrible: Need to keep track of capacity separate from length,
  # and need to store length to be able to handle strings with \0 in the middle.
  def concat(other)
    if (other.is_a?(Fixnum))
      other = other.chr
    else
      other = other.to_s
    end
    %s(do
         (assign ro (callm other __get_raw))
         (assign osize (strlen ro))
         (assign bsize (strlen @buffer))
         (assign size (add bsize osize))
         (assign size (add size 1))
         (assign newb (malloc size))
         (strcpy newb @buffer)
         (strcat newb ro)
         (assign @buffer newb)
   )
    self
  end

  def <<(other)
    concat(other)
  end

  # FIXME: Horribly inefficient 
  def + other
    s = ""
    s << self
    s << other
    s
  end


  def rindex(ch)
    l  = length
    ch = ch.ord
    while l > 0
      l -= 1
      if self[l].ord == ch.ord
        return l
      end
    end
    return nil
  end

  # FIXME: Currently only supports a string pattern
  # of a single character, with a simple string replace
  #
  def gsub(pattern, replacement)
    if pattern.length > 1
      STDERR.puts "WARNING: String#gsub with strings longer than one character not supported"
      exit(1/1)
    end

    str = ""
    pb = pattern[0].ord
    each_byte do |b|
      if b == pb
        str << replacement
      else
        str << b.chr
      end
    end
    str
  end
end

# FIXME: This is an interesting bootstrapping problem
# __get_string can only be called from an s-expression,
# since otherwise "str" will get rewritten to __get_string(str)
# if str is a string constant.
#
# It is still not a satisfactory solution: It ought to never
# be possible to call __set_raw or __get_string directly from
# "normal" Ruby code. Or at the very least a nasty warning
# should be generated. A solution for that might be a pragma
# like the one below (hypothetical, not implemented, indicating
# the call should only be allowed for code generated by the
# compiler)
#
# Another alternative is to implement
#
# pragma compiler-only
%s(defun __get_string (str) (let (s)
  (assign s (callm String new))
  (callm s __set_raw (str))
  s
))
