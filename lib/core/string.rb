
%s(defun __stralloc (len) (do (__alloc_leaf len)))
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

  def initialize *__copysplat
    # @buffer contains the pointer to raw memory
    # used to contain the string.
    # 
    # An s-expression is used rather than = because
    # 0 outside of the s-expression eventually will
    # be an FixNum instance instead of the actual
    # value 0.

    %s(assign @buffer 0)
    @flags  = 0
    @length = 0
    %s(assign @capacity 0)
    %s(if (lt numargs 3)
      (assign @buffer "")
      (callm self __copy_initialize ((splat __copysplat)))
    )
  end

  def __copy_initialize *str
    %s(do
        (assign first (callm str [] ((__int 0))))
        (assign len (callm first length))
        (callm self __copy_raw ((callm first __get_raw) len))
      )
  end

  def inspect
    buf = 34.chr
    esc = 92.chr
    each_byte do |b|
      if b == 34
        buf << esc << 34.chr
      elsif b == 27
        buf << esc << 'e'
      elsif b == 92
        buf << esc << esc
      elsif b == 10
        buf << esc << 'n'
      else
        buf << b.chr
      end
    end
    buf << 34.chr
    buf
  end

  # DJB hash
  def hash
    %s(assign h 5381)
    %s(assign i 0)
    %s(assign len (strlen @buffer))
    %s(while (lt i len) (do
      (assign c (bindex @buffer i))
      (assign h (mul h 33))
      (assign h (add h c))
      (assign i (add i 1))
    ))
    %s(__int h)
  end

  # Original variant.
  def _hash
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

  # FIXME. This is wrong.
  def freeze
    @frozen = true
    self
  end

  # FIXME: We don't support frozen strings yet.
  def frozen?
    @frozen
  end

  def encoding
    # FIXME: Stub - always returns US-ASCII
    # Proper implementation would track actual encoding
    Encoding::US_ASCII
  end

  def [] index
    l = length

    if index.is_a?(Range)
      b = index.first
      e = index.last

      # Convert heap integers to fixnums if within range
      b_fixnum = b.__to_fixnum_if_possible
      if b_fixnum.nil?
        return nil  # Too large/small to be valid string index
      end
      b = b_fixnum

      e_fixnum = e.__to_fixnum_if_possible
      if e_fixnum.nil?
        return nil  # Too large/small to be valid string index
      end
      e = e_fixnum

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
      e = e - b + 1

      a = String.new
      %s(assign src (add @buffer (callm b __get_raw)))
      a.__copy_raw(src, e)
      return a
    end

    # Convert heap integer index to fixnum if within range
    index_fixnum = index.__to_fixnum_if_possible
    if index_fixnum.nil?
      return nil  # Too large/small to be valid string index
    end
    index = index_fixnum

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
    %s(__int c)
  end

  def []= pos, str
    STDERR.puts("ERROR: String#[]= NOT IMPLEMENTED YET; Called with (#{pos},'#{str}')")
    0/0
  end

  def == other
    s = other.is_a?(String)
    return false if !s
    %s(assign res (if (strcmp @buffer (callm other __get_raw)) false true))
    return res
  end

  def eql? other
    %s(if (eq other 0) (do (puts "ERROR: eql? called with zero input\n") (div 1 0)))
    self.==(other)
  end

  def __copy_raw(str,len)
    %s(assign len (add (callm len __get_raw) 1))
    %s(assign @capacity (add len 8))
    %s(assign @buffer (__stralloc @capacity))
    %s(memmove @buffer str len)
    %s(assign (bindex @buffer (sub len 1)) 0)
    nil
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

  def bytes
    result = []
    each_byte do |b|
      result << b
    end
    result
  end

  def map!
    i = 0
    len = length
    while i <  len
      self[i] = yield(self[i])
      i = i + 1
    end
    self
  end

  # FIXME: The documentation for String#<=> in Ruby 2.4.1
  # does not specify *how* this comparison is to be carried
  # out, and I'm not inclined to e.g. try to support encodings
  # at this point, so for the time being this compares strings
  # byte by byte, which is almost guaranteed to be wrong,
  # but this is sufficient to get a lot of code working initially
  #
  # FIXME: This implementation is also inefficient
  #
  def <=> other
    return nil if !other.kind_of?(String)

    i   = 0
    max = length > other.length ? other.length : length

    while i < max
      return -1 if self[i] < other[i]
      return 1  if self[i] > other[i]
      i += 1
    end

    return -1 if i < other.length
    return 1 if length > other.length

    return 0
  end


  def uniq
  end

  def to_s
    self
  end

  def to_str
    self
  end

  def to_sym
    buffer = @buffer
    %s(call __get_symbol buffer)
  end

  def to_i
    num = 0
    i = 0
    len = length
    neg = false
    if self[0] == ?-
      neg = true
      i+=1
    end

    # 30-bit limit (accounting for 1-bit tagging)
    # Stop parsing if number gets too big to prevent overflow
    max_safe = 268435456  # 2^28 - Stop before we overflow

    while i <  len
      s = self[i]
      break if !(?0..?9).member?(s)

      # Stop if next digit would cause overflow
      break if num > max_safe

      num = num*10 + s.ord - 48 # "0" == 48
      i = i + 1
    end
    if neg
      num = num * (-1)
    end
    return num
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

    endp = b + e
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

  def upcase
    result = ""
    i = 0
    l = length
    while i < l
      c = self[i].ord
      # Convert lowercase (a-z: 97-122) to uppercase (A-Z: 65-90)
      if c >= 97 && c <= 122
        c = c - 32
      end
      result << c.chr
      i += 1
    end
    result
  end

  def downcase
    result = ""
    i = 0
    l = length
    while i < l
      c = self[i].ord
      # Convert uppercase (A-Z: 65-90) to lowercase (a-z: 97-122)
      if c >= 65 && c <= 90
        c = c + 32
      end
      result << c.chr
      i += 1
    end
    result
  end

  def start_with?(prefix)
    prefix_len = prefix.length
    return false if prefix_len > length

    i = 0
    while i < prefix_len
      return false if self[i] != prefix[i]
      i += 1
    end
    true
  end

  def end_with?(suffix)
    suffix_len = suffix.length
    my_len = length
    return false if suffix_len > my_len

    offset = my_len - suffix_len
    i = 0
    while i < suffix_len
      return false if self[offset + i] != suffix[i]
      i += 1
    end
    true
  end

  def include?(substring)
    return true if substring.length == 0
    return false if substring.length > length

    my_len = length
    sub_len = substring.length
    max_start = my_len - sub_len

    # Try each possible starting position
    pos = 0
    while pos <= max_start
      # Check if substring matches at this position
      match = true
      i = 0
      while i < sub_len
        if self[pos + i] != substring[i]
          match = false
          break
        end
        i += 1
      end
      return true if match
      pos += 1
    end

    false
  end

  def length
    # FIXME: yes, we should not assume C-strings
    # FIXME: Also, this is not nice if @buffer == -
    %s(assign l (strlen @buffer))
    %s(__int l)
  end

  def size
    length
  end

  def count c = nil
    return length if !c
    l = 0
    c = c.ord
    each_byte do |b|
      if b == c
        l = l + 1
      end
    end
    l
  end

  # FIXME: This is horrible: Need to keep track of capacity separate from length,
  # and need to store length to be able to handle strings with \0 in the middle.
  def concat(other)
    if (other.is_a?(Integer))
      other = other.chr
    else
      other = other.to_s
    end
    %s(do
         (assign ro (callm other __get_raw))
         (assign osize (strlen ro))
         (if (ge osize 1) (do
           (assign bsize (strlen @buffer))
           (assign size (add bsize osize))
           (assign @length size)
           (assign size (add size 1))
           (if (gt size @capacity) (do
               (assign @capacity (add size 8))
               (assign newb (__stralloc @capacity))
               (strcpy newb @buffer)
               (strcat newb ro)
               (assign @buffer newb)
             )
             (do
               (strcat @buffer ro)
             )
           )
         ))
       )
    self
  end

  def <<(other)
    concat(other)
  end

  def dup
    String.new(self)
  end

  # FIXME: Inefficient (should pre-alloc capacity)
  def + other
    dup.concat(other)
  end

  # FIXME: Terribly inefficient (should pre-alloc capacity)
  def * cnt
    s = ""
    cnt.times do
      s.concat(self)
    end
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
      STDERR.puts("WARNING: String#gsub with strings longer than one character not supported")
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

  # Initial, partial implementation.
  # This explicitly ignores a whole load of the
  # full behaviour of #split
  def split(pat = ' ')
    ary = []
    cur = ""
    self.each_byte do |c|
      if c.chr == pat
        ary << cur
        cur = ""
      elsif pat == ' ' && (c == 10 || c == 13 || c == 9)
        ary << cur
        cur = ""
      else
        cur << c.chr
      end
    end
    ary << cur if cur != ""
    ary
  end

  # Helper for %I{} with interpolation - splits string and converts to symbols
  def __percent_I
    split.map { |w| w.to_sym }
  end

  # Remove leading whitespace (space, tab, newline, carriage return)
  # Returns a new string
  def lstrip
    i = 0
    len = length
    while i < len
      c = self[i]
      # Space (32), tab (9), newline (10), carriage return (13)
      break if c != 32 && c != 9 && c != 10 && c != 13
      i += 1
    end
    return "" if i >= len
    self[i..-1]
  end

  # Remove trailing whitespace (space, tab, newline, carriage return)
  # Returns a new string
  def rstrip
    len = length
    return "" if len == 0

    i = len - 1
    while i >= 0
      c = self[i]
      # Space (32), tab (9), newline (10), carriage return (13)
      break if c != 32 && c != 9 && c != 10 && c != 13
      i -= 1
    end
    return "" if i < 0
    self[0..i]
  end

  # Remove leading and trailing whitespace
  # Returns a new string
  def strip
    lstrip.rstrip
  end

  # Remove trailing newline characters (\n, \r, \r\n)
  # Returns a new string
  def chomp(separator = "\n")
    return self if self.length == 0

    # Handle default case: remove \n, \r, or \r\n
    if separator == "\n"
      len = self.length
      if len > 0 && self[len - 1] == "\n"
        # Check for \r\n
        if len > 1 && self[len - 2] == "\r"
          return self[0..-3]
        else
          return self[0..-2]
        end
      elsif len > 0 && self[len - 1] == "\r"
        return self[0..-2]
      end
      return self
    end

    # Handle custom separator
    if separator.length == 0
      # Empty string means remove all trailing newlines
      result = self
      while result.length > 0 && (result[-1] == "\n" || result[-1] == "\r")
        result = result[0..-2]
      end
      return result
    end

    # Remove specific separator if present at end
    if self.length >= separator.length && self[(-separator.length)..-1] == separator
      return self[0..(-separator.length - 1)]
    end

    return self
  end

  # Remove trailing newline characters in place
  # Returns self if modified, nil if no modification made
  def chomp!(separator = "\n")
    original_length = self.length
    result = self.chomp(separator)

    if result.length != original_length
      # Modify self in place using __set_raw
      self.__set_raw(result.__get_raw)
      return self
    end

    return nil
  end

  # FIXME: Stub.
  def force_encoding(encoding)
    encoding
  end

  # Match string against pattern
  # Stub: Returns nil (regexp not implemented)
  # Full implementation would perform regex matching
  def =~(pattern)
    nil
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
