
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

    @flags  = 0
    # @length is the authoritative byte length, stored RAW (not tagged): every %s site
    # below reads/writes it raw. @buffer stays NUL-terminated at @length so C interop
    # (strcmp-free now, but printf/open/... take @buffer) keeps working; NUL bytes
    # INSIDE the string are legal and counted.
    %s(assign @length 0)
    # NB: do NOT null @buffer before the copy branch. For a self-replace (`str.send(:initialize, str)`)
    # the source IS self, so nulling @buffer would make __copy_initialize read a NULL buffer
    # (strlen/memmove on NULL -> segfault, core/string/initialize_spec self-replacing example).
    # __copy_raw allocates a fresh @buffer/@capacity from the source, so the copy path needs no reset;
    # only the no-arg branch initialises @buffer/@capacity.
    %s(if (lt numargs 3)
      (do
        (assign @buffer "")
        (assign @capacity 0))
      (callm self __copy_initialize ((splat __copysplat)))
    )
    # Return self, NOT the value of the `%s(if ...)` above: in the no-arg branch that value is the RAW
    # C string literal `""` (a char*, not a Ruby String), so `str.send(:initialize)` would hand back a
    # bare pointer whose "class slot" is string bytes -> any method call on it dereferences garbage and
    # segfaults (core/string/initialize_spec). MRI's #initialize returns the receiver; String.new ignores
    # this (it uses its own allocation), so returning self is safe.
    self
  end

  def __copy_initialize *str
    first = str[0]
    # The argument need not be a String: MRI coerces via #to_str (StringValue), raising TypeError if it
    # is absent. Without this, a non-String (e.g. an Integer, an Array, or a mock) reached #length /
    # #__get_raw below -- which assume a String buffer -- and segfaulted (core/string/initialize_spec's
    # "tries to convert other to string using to_str" / "raises a TypeError" examples).
    unless first.is_a?(String)
      if first.respond_to?(:to_str)
        first = first.to_str
      else
        raise TypeError.new("no implicit conversion into String")
      end
    end
    __copy_raw(first.__get_raw, first.length)
  end

  def inspect
    buf = 34.chr
    esc = 92.chr
    prev_hash = false
    each_byte do |b|
      if prev_hash
        if b == 123 || b == 36 || b == 64
          buf << esc << 35.chr
        else
          buf << 35.chr
        end
        prev_hash = false
      end
      if b == 34
        buf << esc << 34.chr
      elsif b == 27
        buf << esc << 'e'
      elsif b == 92
        buf << esc << esc
      elsif b == 10
        buf << esc << 'n'
      elsif b == 35
        prev_hash = true
      elsif b == 123 || b == 36 || b == 64
        buf << b.chr
      else
        buf << b.chr
      end
    end
    if prev_hash
      buf << 35.chr
    end
    buf << 34.chr
    buf
  end

  # DJB hash
  def hash
    %s(assign h 5381)
    %s(assign i 0)
    %s(assign len @length)
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

  def [] index, len = nil
    # Two-argument form: str[start, length] -- same selection as #slice.
    if !len.nil?
      return slice(index, len)
    end
    l = length

    if index.is_a?(Range)
      b = index.first
      e = index.last

      # Beginless (..e) / endless (b..) ranges: nil endpoints mean "from 0" / "to the end".
      b = 0 if b.nil?
      endless = e.nil?
      e = -1 if endless

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

      return nil if b > l

      # Normalise the range end into an EXCLUSIVE stop position (one past the last included index),
      # honouring exclude_end?. Previously the end was always treated as inclusive (e = e - b + 1), so an
      # exclusive range like "abcdef"[0...5] wrongly kept 6 characters instead of 5.
      if e < 0
        e = l + e
      end
      stop = (!endless && index.exclude_end?) ? e : e + 1
      if stop > l
        stop = l
      end
      if stop < 0
        stop = 0
      end
      len = stop - b
      if len < 0
        len = 0
      end

      a = String.new
      %s(assign src (add @buffer (callm b __get_raw)))
      a.__copy_raw(src, len)
      return a
    end

    # Coerce a non-Integer index the way MRI does: use #to_int when available, otherwise raise TypeError.
    # Without this, a nil / Hash / Array / mock index fell through to __to_fixnum_if_possible (defined only
    # on Integer) and crashed with "undefined method" instead of raising.
    if !index.is_a?(Integer)
      if index.respond_to?(:to_int)
        index = index.to_int
      else
        raise TypeError.new("no implicit conversion of #{index.class} into Integer")
      end
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

  # String#[]= with an Integer index: replace the single character at `pos` with `str`. `str` may be an
  # Integer (a byte value -> its char), the empty string (deletes the char), or a multi-char string
  # (splices in all of it, growing self). Implemented as a splice + #replace: replace rebuilds @buffer in
  # fresh heap memory, which also sidesteps the read-only-literal-buffer problem that made an in-place
  # byte store segfault on string literals.
  # String#[]= in all its forms. The final argument is the replacement; the earlier one(s) select the
  # span of self to replace:
  #   s[index] = str            (single character)
  #   s[index, length] = str
  #   s[range] = str
  #   s[regexp] = str           (the whole match)
  #   s[substring] = str        (first occurrence)
  # Implemented as a splice through #replace (rebuilds @buffer in fresh heap memory, so it also works on
  # read-only string literals). Returns the replacement value, as assignment expressions do.
  def []=(*args)
    repl = args[args.length - 1]
    repl = repl.is_a?(Integer) ? repl.chr : repl.to_s
    l = length

    if args.length == 3
      start = args[0]
      len = args[1]
      start = l + start if start < 0
      raise IndexError.new("index #{args[0]} out of string") if start < 0 || start > l
      len = 0 if len < 0
      len = l - start if start + len > l
    else
      idx = args[0]
      if idx.is_a?(Range)
        start = idx.first
        start = l + start if start < 0
        raise RangeError.new("#{idx} out of range") if start < 0 || start > l
        e = idx.last
        e = l + e if e < 0
        stop = idx.exclude_end? ? e : e + 1
        stop = l if stop > l
        len = stop - start
        len = 0 if len < 0
      elsif idx.is_a?(Regexp)
        m = match(idx)
        raise IndexError.new("regexp not matched") if m.nil?
        start = m.begin(0)
        len = m[0].length
      elsif idx.is_a?(String)
        start = index(idx)
        raise IndexError.new("string not matched") if start.nil?
        len = idx.length
      else
        start = idx
        start = l + start if start < 0
        raise IndexError.new("index #{idx} out of string") if start < 0 || start >= l
        len = 1
      end
    end

    replace(self[0...start] + repl + self[(start + len)..-1])
    args[args.length - 1]
  end

  # String#succ: successor string for String ranges (e.g. ('0'..'5').to_a) via Range#each. Increments the
  # last byte. Because the byte strictly increases, Range#each terminates correctly for same-length ranges
  # (the common case in specs). NOTE: does NOT implement Ruby's alphabetic/carry wrap ('9'->'10', 'z'->'aa')
  # -- that needs a prepend (String#+) which currently breaks self-host (selftest-c). See memory.
  def succ
    return dup if length == 0
    s = dup
    i = length - 1
    c = s[i]
    s[i] = c + 1
    s
  end

  def == other
    s = other.is_a?(String)
    return false if !s
    return false if length != other.length
    # memcmp over the full byte length: NUL bytes inside the string compare correctly
    # (strcmp stopped at the first NUL).
    olen = length
    %s(assign res (if (memcmp @buffer (callm other __get_raw) (callm olen __get_raw)) false true))
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
    # NOTE: @length must be derived BEFORE the bindex terminator store below --
    # compiling the (bindex .. (sub len 1)) statement clobbers the `len` local
    # (register writeback), so deriving from `len` after it is off by one.
    %s(assign @length (sub len 1))
    %s(assign (bindex @buffer @length) 0)
    nil
   end

  def __set_raw(str)
    @buffer = str
    # Rebind @capacity to the new buffer. Leaving it at the previous value is unsafe: concat trusts
    # @capacity to decide between an in-place append and a realloc, so a stale (larger) capacity after
    # the buffer shrinks lets a later `<<` write past the new allocation and corrupt the heap. A
    # conservative capacity (valid length + 1) never overflows -- concat just reallocs when it must.
    # This is the C-STRING entry point (literals, getenv, ...) so strlen defines the length;
    # NUL-containing strings must go through __copy_raw/__set_len instead.
    %s(assign @length (strlen @buffer))
    %s(assign @capacity (add @length 1))
  end

  # Runtime internal: set the byte length explicitly, for buffers written raw that may
  # contain NUL bytes (e.g. Integer#chr of 0). The caller guarantees @buffer holds (at
  # least) l bytes plus a NUL terminator.
  def __set_len(l)
    %s(assign @length (callm l __get_raw))
    self
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
    raise ArgumentError.new("Empty string") if empty?

    # FIXME: This is 1.8.x behaviour; for 1.9.x, String[] behaviur changes, and
    # we ned to change this accordingly.
    self[0]
  end

  def each_byte(&block)
    return to_enum(:each_byte) if !block
    i = 0
    len = length
    while i <  len
      block.call(self[i])
      i = i + 1
    end
    self
  end

  # Digit value of a char code (0-9a-z / A-Z), or -1 if not a digit/letter.
  def __digit_val(c)
    if c >= 48 && c <= 57
      c - 48
    elsif c >= 97 && c <= 122
      c - 87
    elsif c >= 65 && c <= 90
      c - 55
    else
      -1
    end
  end

  # Parse a leading numeric literal in the given base (with optional sign and an underscore-between-digits
  # rule). radix_prefix, when true, honours a 0x/0b/0o/0d prefix (used by #oct). Stops at the first
  # non-matching character (returning 0 for no digits), as MRI's #hex/#oct do -- they never raise.
  def __parse_radix(base, allow_prefix)
    s = strip
    n = s.length
    i = 0
    neg = false
    if i < n && (s[i] == 43 || s[i] == 45)
      neg = s[i] == 45
      i = i + 1
    end
    b = base
    if allow_prefix && i + 1 < n && s[i] == 48
      c = s[i + 1]
      if c == 120 || c == 88
        b = 16; i = i + 2
      elsif c == 98 || c == 66
        b = 2; i = i + 2
      elsif c == 111 || c == 79
        b = 8; i = i + 2
      elsif c == 100 || c == 68
        b = 10; i = i + 2
      end
    elsif !allow_prefix && i + 1 < n && s[i] == 48 && (s[i + 1] == 120 || s[i + 1] == 88) && base == 16
      i = i + 2   # #hex accepts a leading 0x
    end
    val = 0
    while i < n
      c = s[i]
      if c == 95
        i = i + 1
      else
        d = __digit_val(c)
        break if d < 0 || d >= b
        val = val * b + d
        i = i + 1
      end
    end
    neg ? -val : val
  end

  # Interpret leading characters as a hexadecimal integer (0 if none).
  def hex
    __parse_radix(16, false)
  end

  # Interpret leading characters as an octal integer, honouring 0x/0b/0o/0d prefixes (0 if none).
  def oct
    __parse_radix(8, true)
  end

  def bytes
    result = []
    each_byte do |b|
      result << b
    end
    result
  end

  # Codepoints (byte-oriented: one per character). grapheme clusters == characters here.
  def codepoints
    result = []
    each_char { |c| result << c.ord }
    result
  end

  def each_codepoint(&block)
    return to_enum(:each_codepoint) if !block
    each_char { |c| block.call(c.ord) }
    self
  end

  def grapheme_clusters
    chars
  end

  def each_grapheme_cluster(&block)
    return to_enum(:each_grapheme_cluster) if !block
    each_char(&block)
    self
  end

  # First element of #unpack(format).
  def unpack1(format)
    unpack(format)[0]
  end

  # Yield each character (as a 1-char String -- note self[i] returns a byte value, so use slice) to
  # the block, returning self; with no block, return an Enumerator.
  def each_char
    return to_enum(:each_char) if !block_given?
    i = 0
    len = length
    while i < len
      yield slice(i, 1)
      i = i + 1
    end
    self
  end

  # With no block, return an Array of the characters; with a block, yield each and return self.
  def chars
    result = []
    i = 0
    len = length
    while i < len
      result << slice(i, 1)
      i = i + 1
    end
    return result if !block_given?
    i = 0
    while i < len
      yield result[i]
      i = i + 1
    end
    self
  end

  def bytesize
    length
  end

  # Case-insensitive comparison (ASCII case folding, like our upcase/downcase).
  # Returns -1/0/1, or nil when other is not string-convertible.
  def casecmp(other)
    if !other.is_a?(String)
      return nil if !other.respond_to?(:to_str)
      other = other.to_str
    end
    downcase <=> other.downcase
  end

  def casecmp?(other)
    r = casecmp(other)
    return nil if r.nil?
    r == 0
  end

  # Byte at index i as an unsigned 0..255 value (nil if out of range). self[i] yields a possibly-signed
  # char code, so fold negatives back into 0..255.
  def getbyte(i)
    i = length + i if i < 0
    return nil if i < 0 || i >= length
    b = self[i]
    b < 0 ? b + 256 : b
  end

  def setbyte(i, b)
    i = length + i if i < 0
    self[i] = b & 255
    b
  end

  # Substring by byte offset. Byte- and char-indexing coincide in this runtime, so this defers to the
  # range/slice forms of #[]. byteslice(i) is a single-byte string; byteslice(i, len) / byteslice(range)
  # are substrings.
  def byteslice(start, len = nil)
    return self[start] if start.is_a?(Range)
    if len.nil?
      s = start < 0 ? length + start : start
      return nil if s < 0 || s >= length
      return self[s..s]
    end
    return nil if len < 0
    s = start < 0 ? length + start : start
    return nil if s < 0 || s > length
    self[s...(s + len)]
  end

  # Prepend the given strings to self in place, returning self.
  def prepend(*others)
    pre = ""
    others.each { |o| pre = pre + o.to_s }
    replace(pre + self)
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

  # Shared numeric-string parser behind String#to_i and Kernel#Integer.
  # base 0 = auto-detect from a 0x/0o/0b/0 prefix (default decimal).
  # strict: the WHOLE string (modulo surrounding whitespace) must be a valid
  # numeral -> returns nil on any violation (Kernel#Integer raises on nil).
  # lenient: skip leading whitespace, parse the longest valid prefix, 0 if none.
  # Digits accumulate through ordinary Integer arithmetic, so bignums work.
  def __parse_int(base, strict)
    i = 0
    len = length
    # leading whitespace
    while i < len && (self[i] == 32 || (self[i] >= 9 && self[i] <= 13))
      i += 1
    end
    neg = false
    if i < len && (self[i] == 45 || self[i] == 43)   # '-' / '+'
      neg = self[i] == 45
      i += 1
    end
    # prefix / base detection
    if i + 1 < len && self[i] == 48                   # '0'
      c = self[i + 1]
      if c == 120 || c == 88                          # x X
        if base == 0 || base == 16
          base = 16
          i += 2
        end
      elsif c == 111 || c == 79                       # o O
        if base == 0 || base == 8
          base = 8
          i += 2
        end
      elsif c == 98 || c == 66                        # b B
        if base == 0 || base == 2
          base = 2
          i += 2
        end
      elsif c == 100 || c == 68                       # d D
        if base == 0 || base == 10
          base = 10
          i += 2
        end
      elsif base == 0
        base = 8
      end
    end
    base = 10 if base == 0
    num = 0
    ndigits = 0
    # NOTE: integer flag, not a boolean local -- a boolean here hit the known
    # false-object-truthiness miscompile (the second consecutive underscore
    # sailed through the guard).
    lastu = 0
    while i < len
      c = self[i]
      if c == 95                                      # '_'
        # single underscores between digits only
        if ndigits == 0 || lastu == 1
          return nil if strict
          break
        end
        lastu = 1
        i += 1
      else
        v = nil
        if c >= 48 && c <= 57
          v = c - 48
        elsif c >= 97 && c <= 122
          v = c - 87
        elsif c >= 65 && c <= 90
          v = c - 55
        end
        if v.nil? || v >= base
          break
        end
        num = num * base + v
        ndigits += 1
        lastu = 0
        i += 1
      end
    end
    if strict
      return nil if ndigits == 0
      return nil if lastu == 1
      # only trailing whitespace may remain
      while i < len && (self[i] == 32 || (self[i] >= 9 && self[i] <= 13))
        i += 1
      end
      return nil if i != len
    end
    if neg
      num = 0 - num
    end
    num
  end

  # String#to_i(base = 10): lenient longest-prefix parse (0 when no digits).
  def to_i(base = 10)
    if !base.is_a?(Integer)
      raise TypeError, "no implicit conversion of #{base.class} into Integer" if !base.respond_to?(:to_int)
      base = base.to_int
    end
    raise ArgumentError, "invalid radix #{base}" if base < 0 || base == 1 || base > 36
    r = __parse_int(base, false)
    return 0 if r.nil?
    r
  end

  def slice!(b, e = nil)
    l = length
    # Range form: slice!(2..), slice!(1..-2), ... -- normalize to (start, length)
    if b.is_a?(Range)
      s = b.begin
      s = 0 if s.nil?
      s = l + s if s < 0
      re = b.end
      if re.nil?
        e = l - s
      else
        re = l + re if re < 0
        re = re + 1 if !b.exclude_end?
        e = re - s
      end
      e = 0 if e < 0
      b = s
    elsif e.nil?
      # Single index: remove one character
      e = 1
    end
    if b < 0
      b = l + b
    end
    if b < 0 || b > l
      return nil
    end
    if b + e > l
      e = l - b
    end
    removed = slice(b, e)
    rest = slice(0, b)
    rest.concat(slice(b + e, l - b - e))
    self.__set_raw(rest.__get_raw)
    removed
  end

  def slice(a, len = nil)
    # Regexp form: slice(re) returns the whole match; slice(re, n) returns capture group n. nil if no match.
    if a.is_a?(Regexp)
      m = match(a)
      return nil if m.nil?
      return len.nil? ? m[0] : m[len]
    end
    # String form: slice(str) returns a copy of str if it occurs in self, else nil.
    if a.is_a?(String)
      return include?(a) ? String.new(a) : nil
    end
    return self[a] if len.nil?
    l = length
    start = a < 0 ? l + a : a
    return nil if start < 0 || start > l || len < 0
    len = l - start if start + len > l
    n = String.new
    %s(assign src (add @buffer (callm start __get_raw)))
    n.__copy_raw(src, len)
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

  # In-place #upcase. Returns self if any character changed, nil otherwise (mirrors MRI's bang methods).
  def upcase!
    r = upcase
    return nil if r == self
    replace(r)
    self
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

  # In-place #downcase. Returns self if any character changed, nil otherwise.
  def downcase!
    r = downcase
    return nil if r == self
    replace(r)
    self
  end

  # Upcase the first character and downcase the rest (ASCII).
  def capitalize
    return dup if length == 0
    result = ""
    i = 0
    l = length
    while i < l
      c = self[i].ord
      if i == 0
        c = c - 32 if c >= 97 && c <= 122
      else
        c = c + 32 if c >= 65 && c <= 90
      end
      result << c.chr
      i += 1
    end
    result
  end

  def capitalize!
    r = capitalize
    return nil if r == self
    replace(r)
    self
  end

  # Swap the case of every ASCII letter.
  def swapcase
    result = ""
    i = 0
    l = length
    while i < l
      c = self[i].ord
      if c >= 97 && c <= 122
        c = c - 32
      elsif c >= 65 && c <= 90
        c = c + 32
      end
      result << c.chr
      i += 1
    end
    result
  end

  def swapcase!
    r = swapcase
    return nil if r == self
    replace(r)
    self
  end

  # True if the string starts with ANY of the given prefixes (String or Regexp).
  def start_with?(*prefixes)
    prefixes.each do |prefix|
      if prefix.is_a?(Regexp)
        m = prefix.match(self, 0)
        return true if !m.nil? && m.begin(0) == 0
      else
        p = prefix.to_s
        pl = p.length
        if pl <= length
          matched = true
          i = 0
          while i < pl
            if self[i] != p[i]
              matched = false
              break
            end
            i += 1
          end
          return true if matched
        end
      end
    end
    false
  end

  # Remove the last character (or a trailing "\r\n" pair) and return the result.
  def chop
    n = length
    return dup if n == 0
    if n >= 2 && self[n - 2] == 13 && self[n - 1] == 10
      self[0...(n - 2)]
    else
      self[0...(n - 1)]
    end
  end

  def chop!
    r = chop
    return nil if r == self
    replace(r)
    self
  end

  # True if the string ends with ANY of the given (String) suffixes.
  def end_with?(*suffixes)
    my_len = length
    suffixes.each do |suffix|
      s = suffix.to_s
      sl = s.length
      if sl <= my_len
        offset = my_len - sl
        matched = true
        i = 0
        while i < sl
          if self[offset + i] != s[i]
            matched = false
            break
          end
          i += 1
        end
        return true if matched
      end
    end
    false
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
    %s(__int @length)
  end

  def size
    length
  end

  # Shared character-set parsing for count/delete/squeeze arguments: returns [negated, chars] where chars
  # is the expanded character list (ranges via __tr_expand) and negated is set when the spec begins with
  # '^'. (String#[] yields a char CODE here, so the leading '^' is compared as 94.)
  def __charset_spec(spec)
    s = spec.to_str
    neg = false
    if s.length > 0 && s[0] == 94
      neg = true
      s = s.slice(1, s.length - 1)
    end
    [neg, __tr_expand(s)]
  end

  def __charset_has?(cs, ch)
    member = !cs[1].index(ch).nil?
    cs[0] ? !member : member
  end

  # Count characters that are in ALL the given sets (Ruby intersects multiple set arguments).
  def count(*sets)
    return length if sets.empty?
    css = sets.map { |s| __charset_spec(s) }
    n = 0
    each_char do |ch|
      n = n + 1 if css.all? { |cs| __charset_has?(cs, ch) }
    end
    n
  end

  # Replace this string's contents in place with `other`'s (String#replace), returning self.
  def replace(other)
    o = other.to_s
    olen = o.length
    %s(do
      (assign ro (callm o __get_raw))
      (assign osize (callm olen __get_raw))
      (assign @capacity (add osize 8))
      (assign @buffer (__stralloc @capacity))
      (memmove @buffer ro osize)
      (assign (bindex @buffer osize) 0)
      (assign @length osize)
    )
    self
  end

  # Remove every character that is in ALL the given sets.
  def delete(*sets)
    css = sets.map { |s| __charset_spec(s) }
    out = ""
    each_char do |ch|
      out = out + ch unless css.all? { |cs| __charset_has?(cs, ch) }
    end
    out
  end

  # In-place delete; returns self if anything was removed, else nil.
  def delete!(*sets)
    r = delete(*sets)
    return nil if r == self
    replace(r)
    self
  end

  # Collapse runs of the same character. With no argument every run is squeezed; with set arguments only
  # runs of characters that are in ALL the sets are squeezed.
  def squeeze(*sets)
    css = sets.empty? ? nil : sets.map { |s| __charset_spec(s) }
    out = ""
    prev = nil
    each_char do |ch|
      matched = css.nil? || css.all? { |cs| __charset_has?(cs, ch) }
      out = out + ch unless ch == prev && matched
      prev = ch
    end
    out
  end

  # In-place squeeze; returns self if anything was collapsed, else nil.
  def squeeze!(*sets)
    r = squeeze(*sets)
    return nil if r == self
    replace(r)
    self
  end

  def concat(other)
    if (other.is_a?(Integer))
      other = other.chr
    else
      other = other.to_s
    end
    olen = other.length
    %s(do
         (assign ro (callm other __get_raw))
         (assign osize (callm olen __get_raw))
         (if (ge osize 1) (do
           (assign bsize @length)
           (assign size (add bsize osize))
           (assign size (add size 1))
           (if (gt size @capacity) (do
               (assign @capacity (add size 8))
               (assign newb (__stralloc @capacity))
               (memmove newb @buffer bsize)
               (assign @buffer newb)
             ))
           (memmove (add @buffer bsize) ro osize)
           (assign @length (add bsize osize))
           (assign (bindex @buffer @length) 0)
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

  # Unary plus returns self for mutable strings, or a mutable copy for frozen
  def +@
    self
  end

  # Unary minus returns a frozen copy (or self if already frozen)
  def -@
    # FIXME: We don't have frozen? / freeze implemented yet
    # For now, just return a frozen duplicate
    dup.freeze
  end

  # FIXME: Inefficient (should pre-alloc capacity)
  def + other
    dup.concat(other)
  end

  # FIXME: Terribly inefficient (should pre-alloc capacity)
  def * cnt
    raise ArgumentError, "negative argument" if cnt < 0
    # Guard against building an absurdly large string. Without this, `"abc" * (2**31-1)` loops ~2e9 times
    # allocating gigabytes -> effectively a hang. MRI raises RangeError when the multiplier does not fit in
    # a long, and ArgumentError when the RESULT length would overflow a long.
    if cnt > 0x7fffffff
      raise RangeError, "bignum too big to convert into `long'"
    end
    # An empty string repeated any (long-sized) number of times is still "" -- return immediately instead
    # of looping cnt times over a no-op concat (`"" * max_long` otherwise spins ~2e9 times). This is after
    # the Bignum check so `"" * <bignum>` still raises RangeError.
    return "" if length == 0
    if cnt > (0x7fffffff / length)
      raise ArgumentError, "argument too big"
    end
    s = ""
    cnt.times do
      s.concat(self)
    end
    s
  end

  # Coerce a justification width to an Integer (via #to_int), raising TypeError otherwise.
  def __just_width(width)
    return width if width.is_a?(Integer)
    if width.respond_to?(:to_int)
      r = width.to_int
      return r if r.is_a?(Integer)
    end
    raise TypeError.new("no implicit conversion into Integer")
  end

  # Coerce a pad string (via #to_str), raising TypeError for non-strings and ArgumentError when empty.
  def __just_pad(padstr)
    if !padstr.is_a?(String)
      if padstr.respond_to?(:to_str)
        padstr = padstr.to_str
      else
        raise TypeError.new("no implicit conversion into String")
      end
    end
    raise ArgumentError.new("zero width padding") if padstr.empty?
    padstr
  end

  # Build a fresh String of exactly n characters by repeating padstr and truncating.
  def __pad_fill(padstr, n)
    s = ""
    return s if n <= 0
    while s.length < n
      s.concat(padstr)
    end
    s.slice(0, n)
  end

  def ljust(width, padstr = " ")
    width = __just_width(width)
    padstr = __just_pad(padstr)
    len = length
    return dup if width <= len
    dup.concat(__pad_fill(padstr, width - len))
  end

  def rjust(width, padstr = " ")
    width = __just_width(width)
    padstr = __just_pad(padstr)
    len = length
    return dup if width <= len
    __pad_fill(padstr, width - len).concat(self)
  end

  def center(width, padstr = " ")
    width = __just_width(width)
    padstr = __just_pad(padstr)
    len = length
    return dup if width <= len
    total = width - len
    left = total / 2
    right = total - left
    result = __pad_fill(padstr, left)
    result.concat(self)
    result.concat(__pad_fill(padstr, right))
    result
  end

  # Insert `other` before the character at `index`, modifying self in place and returning self.
  # A negative index counts from the end such that -1 appends after the last character.
  def insert(index, other)
    index = __just_width(index)
    if !other.is_a?(String)
      if other.respond_to?(:to_str)
        other = other.to_str
      else
        raise TypeError.new("no implicit conversion into String")
      end
    end
    len = length
    pos = index < 0 ? len + index + 1 : index
    if pos < 0 || pos > len
      raise IndexError.new("index out of string")
    end
    head = slice(0, pos)
    head.concat(other)
    head.concat(slice(pos, len - pos))
    self.__set_raw(head.__get_raw)
    self
  end


  # Last index of a String or Regexp match at or before `stop` (default end of string), or nil.
  def rindex(needle, stop = nil)
    n = length
    stop = n if stop.nil?
    stop = n + stop if stop < 0
    return nil if stop < 0
    if needle.is_a?(Regexp)
      last = nil
      pos = 0
      while pos <= n
        m = needle.match(self, pos)
        break if m.nil?
        b = m.begin(0)
        break if b > stop
        last = b
        e = m.end(0)
        pos = e > b ? e : e + 1
      end
      return last
    end
    needle = needle.to_str if !needle.is_a?(String) && needle.respond_to?(:to_str)
    slen = needle.length
    return (stop > n ? n : stop) if slen == 0
    last = nil
    pos = 0
    while true
      idx = __substr_index(needle, pos)
      break if idx.nil? || idx > stop
      last = idx
      pos = idx + 1
    end
    last
  end

  # Byte-wise search for the first occurrence of substring `sub` at or after `start`; nil if absent.
  def __substr_index(sub, start)
    my_len = length
    sub_len = sub.length
    return start if sub_len == 0
    return nil if sub_len > my_len
    pos = start
    pos = 0 if pos < 0
    max_start = my_len - sub_len
    while pos <= max_start
      match = true
      i = 0
      while i < sub_len
        if self[pos + i] != sub[i]
          match = false
          break
        end
        i = i + 1
      end
      return pos if match
      pos = pos + 1
    end
    nil
  end

  # Byte-wise search for the LAST occurrence of substring `sub`; nil if absent.
  def __substr_rindex(sub)
    my_len = length
    sub_len = sub.length
    return my_len if sub_len == 0
    return nil if sub_len > my_len
    pos = my_len - sub_len
    while pos >= 0
      match = true
      i = 0
      while i < sub_len
        if self[pos + i] != sub[i]
          match = false
          break
        end
        i = i + 1
      end
      return pos if match
      pos = pos - 1
    end
    nil
  end

  # Coerce a partition separator to a String (via #to_str), raising TypeError otherwise.
  # Regexp separators are not yet supported (Regexp has no #to_str -> TypeError).
  def __partition_sep(sep)
    return sep if sep.is_a?(String)
    return sep.to_str if sep.respond_to?(:to_str)
    raise TypeError.new("type mismatch: separant is not a String")
  end

  # Split self at the FIRST occurrence of sep into [before, sep, after]; [self, "", ""] if absent.
  def partition(sep)
    if sep.is_a?(Regexp)
      m = sep.match(self)
      return [dup, "", ""] if m.nil?
      b = m.begin(0)
      e = m.end(0)
      return [slice(0, b), slice(b, e - b), slice(e, length - e)]
    end
    sep = __partition_sep(sep)
    idx = __substr_index(sep, 0)
    return [dup, "", ""] if idx.nil?
    slen = sep.length
    [slice(0, idx), slice(idx, slen), slice(idx + slen, length - idx - slen)]
  end

  # Split self at the LAST occurrence of sep into [before, sep, after]; ["", "", self] if absent.
  def rpartition(sep)
    if sep.is_a?(Regexp)
      # Scan left-to-right keeping the LAST match (the engine has no right-anchored search).
      last = nil
      pos = 0
      n = length
      while pos <= n
        m = sep.match(self, pos)
        break if m.nil?
        last = m
        e = m.end(0)
        pos = e > m.begin(0) ? e : e + 1
      end
      return ["", "", dup] if last.nil?
      b = last.begin(0)
      e = last.end(0)
      return [slice(0, b), slice(b, e - b), slice(e, length - e)]
    end
    sep = __partition_sep(sep)
    idx = __substr_rindex(sep)
    return ["", "", dup] if idx.nil?
    slen = sep.length
    [slice(0, idx), slice(idx, slen), slice(idx + slen, length - idx - slen)]
  end

  # First byte index of `needle` (a String, or anything with #to_str) at or after `offset`; nil if
  # absent. Overrides the nil-returning Object#index stub. (Regexp needles are not yet supported.)
  def index(needle, offset = 0)
    len = length
    offset = offset.to_int if !offset.is_a?(Integer)
    if offset < 0
      offset = len + offset
      return nil if offset < 0
    end
    return nil if offset > len
    if needle.is_a?(Regexp)
      m = needle.match(self, offset)
      return m.nil? ? nil : m.begin(0)
    end
    if needle.is_a?(String)
      str = needle
    elsif needle.respond_to?(:to_str)
      str = needle.to_str
    else
      raise TypeError.new("type mismatch: given object is not a String")
    end
    __substr_index(str, offset)
  end

  # FIXME: Currently only supports a string pattern
  # of a single character, with a simple string replace
  #
  # Expand a tr-style set into an array of single-char strings: "a-c" -> ["a","b","c"].
  # A backslash escapes the following character (so "\\-" is a literal hyphen).
  def __tr_expand(set)
    out = []
    cs = set.chars
    i = 0
    n = cs.length
    while i < n
      if cs[i] == "\\" && i + 1 < n
        out << cs[i + 1]
        i = i + 2
      elsif i + 2 < n && cs[i + 1] == "-"
        lo = cs[i].ord
        hi = cs[i + 2].ord
        c = lo
        while c <= hi
          out << c.chr
          c = c + 1
        end
        i = i + 3
      else
        out << cs[i]
        i = i + 1
      end
    end
    out
  end

  # "fmt" % arg -> sprintf-style formatting (arg is a single value or an Array of values).
  def %(arg)
    args = arg.is_a?(Array) ? arg : [arg]
    __sprintf(self, args)
  end

  # tr(from, to): translate characters. Supports ranges ("a-z"), a leading "^" in `from` to
  # negate the set, and a shorter `to` (its last char repeats). An empty `to` deletes the matches.
  def tr(from_str, to_str)
    from = from_str.to_str
    negate = false
    if from.length > 0 && from[0] == 94  # leading '^' (String#[] yields a char CODE here, not "^")
      negate = true
      from = from.slice(1, from.length - 1)
    end
    from_chars = __tr_expand(from)
    to_chars = to_str.nil? ? [] : __tr_expand(to_str.to_str)
    tlen = to_chars.length
    result = ""
    each_char do |ch|
      idx = from_chars.index(ch)
      matched = negate ? idx.nil? : !idx.nil?
      if matched
        if tlen == 0
          # deletion: emit nothing
        elsif negate
          result = result + to_chars[tlen - 1]
        else
          ti = idx
          ti = tlen - 1 if ti >= tlen
          result = result + to_chars[ti]
        end
      else
        result = result + ch
      end
    end
    result
  end

  # Replace the first (sub) / every (gsub) occurrence of pattern. pattern may be a String (matched
  # literally) or a Regexp. With a block, the matched text is yielded and the block's result substituted;
  # otherwise `replacement` is used, expanding \0-\9 / \& backreferences for regex matches.
  def sub(pattern, replacement = nil, &block)
    if pattern.is_a?(String)
      __sub_gsub_string(pattern, replacement, false, block)
    else
      __sub_gsub_regex(pattern, replacement, false, block)
    end
  end

  def gsub(pattern, replacement = nil, &block)
    if pattern.is_a?(String)
      __sub_gsub_string(pattern, replacement, true, block)
    else
      __sub_gsub_regex(pattern, replacement, true, block)
    end
  end

  # In-place #sub / #gsub. Return self if a substitution was made, nil otherwise (mirrors MRI).
  def sub!(pattern, replacement = nil, &block)
    r = sub(pattern, replacement, &block)
    return nil if r == self
    replace(r)
    self
  end

  def gsub!(pattern, replacement = nil, &block)
    r = gsub(pattern, replacement, &block)
    return nil if r == self
    replace(r)
    self
  end

  # Expand \0-\9 (capture groups; \0 / \& = whole match) and \\ in a regex replacement string. String#[]
  # returns a character CODE here, so bytes are compared numerically ('\\'=92, '0'=48..'9'=57, '&'=38).
  def __expand_replacement(rep, m)
    out = ""
    i = 0
    n = rep.length
    while i < n
      c = rep[i]
      if c == 92 && (i + 1) < n
        nc = rep[i + 1]
        if nc >= 48 && nc <= 57
          grp = m[nc - 48]
          out = out + grp if grp
          i = i + 2
        elsif nc == 38
          out = out + m.to_s
          i = i + 2
        elsif nc == 92
          out = out + "\\"
          i = i + 2
        else
          out = out + c.chr
          i = i + 1
        end
      else
        out = out + c.chr
        i = i + 1
      end
    end
    out
  end

  # String#scan(pattern) -> every non-overlapping match. Without capture groups each element is the matched
  # string; with groups each element is the array of that match's captures. A block yields each element and
  # scan returns self. pattern may be a String (literal, via Regexp) or a Regexp.
  def scan(pattern, &block)
    pattern = Regexp.new(pattern) if pattern.is_a?(String)
    results = []
    pos = 0
    len = length
    while pos <= len
      m = pattern.match(self, pos)
      break if m.nil?
      b = m.begin(0)
      e = m.end(0)
      caps = m.captures
      elem = caps.length > 0 ? caps : m.to_s
      if block
        block.call(elem)
      else
        results << elem
      end
      pos = e > b ? e : e + 1
    end
    block ? self : results
  end

  def __sub_gsub_string(pat, replacement, global, block)
    out = ""
    pos = 0
    len = length
    plen = pat.length
    going = true
    while going
      idx = index(pat, pos)
      if idx.nil?
        out = out + self[pos..-1] if pos < len
        going = false
      else
        out = out + self[pos...idx] if idx > pos
        out = out + (block ? block.call(pat).to_s : replacement)
        pos = idx + plen
        if plen == 0
          out = out + self[pos].chr if pos < len
          pos = pos + 1
        end
        if !global
          out = out + self[pos..-1] if pos < len
          going = false
        end
      end
    end
    out
  end

  def __sub_gsub_regex(pattern, replacement, global, block)
    out = ""
    pos = 0
    len = length
    going = true
    while going && pos <= len
      m = pattern.match(self, pos)
      if m.nil?
        going = false
      else
        b = m.begin(0)
        e = m.end(0)
        out = out + self[pos...b] if b > pos
        out = out + (block ? block.call(m.to_s).to_s : __expand_replacement(replacement, m))
        if e > b
          pos = e
        else
          out = out + self[e].chr if e < len
          pos = e + 1
        end
        going = false if !global
      end
    end
    out = out + self[pos..-1] if pos < len
    out
  end

  # Split into fields. pattern: nil or a single space " " -> awk-style split on runs of whitespace
  # (leading whitespace ignored, no empty fields); "" -> split into characters; any other String ->
  # literal separator; Regexp -> split at each match. limit > 0 caps the number of fields (last field
  # keeps the remainder); limit == 0 (default) drops trailing empty fields; limit < 0 keeps them.
  def split(pattern = nil, limit = 0)
    if pattern.nil? || pattern == " "
      return __split_ws(limit)
    end
    if pattern.is_a?(String)
      return __split_chars(limit) if pattern.empty?
      return __split_string(pattern, limit)
    end
    __split_regex(pattern, limit)
  end

  # Yield each line (including its trailing separator). sep defaults to "\n"; nil yields the whole string.
  def each_line(sep = "\n", &block)
    return to_enum(:each_line, sep) if !block
    if sep.nil?
      block.call(dup)
      return self
    end
    n = length
    if sep == ""
      # Paragraph mode: split on runs of 2+ newlines (blank lines). Leading blank lines are skipped and
      # each yielded paragraph keeps its trailing newline run. The generic loop below would use a
      # separator length of 0, so `start` would never advance -> infinite loop. NB: this runtime's
      # String#[index] returns the BYTE value (Integer), so compare against 10 (the "\n" byte), not "\n".
      nl = 10
      start = 0
      while start < n
        while start < n && self[start] == nl
          start = start + 1
        end
        break if start >= n
        para_start = start
        while start < n
          if self[start] == nl && start + 1 < n && self[start + 1] == nl
            start = start + 1
            while start < n && self[start] == nl
              start = start + 1
            end
            break
          end
          start = start + 1
        end
        block.call(self[para_start...start])
      end
      return self
    end
    start = 0
    sl = sep.length
    while start < n
      idx = index(sep, start)
      if idx.nil?
        block.call(self[start..-1])
        start = n
      else
        block.call(self[start...(idx + sl)])
        start = idx + sl
      end
    end
    self
  end

  def lines(sep = "\n")
    result = []
    each_line(sep) { |l| result << l }
    result
  end

  # tr followed by squeezing runs of characters that were produced by the translation.
  def tr_s(from_str, to_str)
    from = from_str.to_str
    negate = false
    if from.length > 0 && from[0] == 94
      negate = true
      from = from.slice(1, from.length - 1)
    end
    from_chars = __tr_expand(from)
    to_chars = to_str.nil? ? [] : __tr_expand(to_str.to_str)
    tlen = to_chars.length
    result = ""
    prev = nil
    prev_tr = false
    each_char do |ch|
      idx = from_chars.index(ch)
      matched = negate ? idx.nil? : !idx.nil?
      if matched
        rep = nil
        if tlen == 0
          rep = nil
        elsif negate
          rep = to_chars[tlen - 1]
        else
          ti = idx
          ti = tlen - 1 if ti >= tlen
          rep = to_chars[ti]
        end
        if rep.nil?
          # deletion: emit nothing
        elsif prev_tr && rep == prev
          # squeeze consecutive translated duplicates
        else
          result = result + rep
          prev = rep
        end
        prev_tr = true
      else
        result = result + ch
        prev = ch
        prev_tr = false
      end
    end
    result
  end

  def __split_ws(limit)
    result = []
    cur = ""
    i = 0
    n = length
    while i < n
      c = self[i]
      if (c == 32 || c == 9 || c == 10 || c == 13 || c == 12) &&
         !(limit > 0 && result.length >= limit - 1)
        result << cur if cur.length > 0
        cur = ""
      else
        cur << c.chr
      end
      i = i + 1
    end
    result << cur if cur.length > 0
    result
  end

  def __split_chars(limit)
    result = []
    i = 0
    n = length
    while i < n
      if limit > 0 && result.length >= limit - 1
        result << self[i..-1]
        return result
      end
      result << self[i].chr
      i = i + 1
    end
    result
  end

  def __split_string(pat, limit)
    result = []
    pos = 0
    n = length
    plen = pat.length
    while limit <= 0 || result.length < limit - 1
      idx = index(pat, pos)
      break if idx.nil?
      result << self[pos...idx]
      pos = idx + plen
    end
    result << (pos <= n ? self[pos..-1] : "")
    __trim_trailing_empty(result) if limit == 0
    result
  end

  def __split_regex(pattern, limit)
    result = []
    pos = 0
    n = length
    while limit <= 0 || result.length < limit - 1
      m = pattern.match(self, pos)
      break if m.nil?
      b = m.begin(0)
      e = m.end(0)
      if e == b
        # Zero-width match: split between characters. Avoid an infinite loop at end-of-string.
        break if b >= n
        if b > pos
          result << self[pos...b]
        else
          result << self[b].chr
        end
        pos = b > pos ? b : b + 1
      else
        result << self[pos...b]
        pos = e
      end
    end
    result << (pos <= n ? self[pos..-1] : "")
    __trim_trailing_empty(result) if limit == 0
    result
  end

  def __trim_trailing_empty(result)
    while result.length > 0 && result[result.length - 1] == ""
      result.pop
    end
    result
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
  # Byte-oriented runtime: we do not transcode, so force_encoding just returns self (MRI returns self too;
  # the previous code returned the ENCODING argument, so `str.force_encoding('X').foo` called foo on the
  # encoding object and crashed). encode returns a fresh copy of the bytes.
  def force_encoding(encoding)
    self
  end

  # Byte-oriented runtime: every byte sequence is "valid", so valid_encoding? is always true and scrub
  # (which replaces invalid byte sequences) is a plain copy. ascii_only? is a real check: no byte >= 128.
  def valid_encoding?
    true
  end

  def ascii_only?
    # each_byte may yield signed bytes, so a high byte (>= 128) can appear as a negative number.
    each_byte { |b| return false if b >= 128 || b < 0 }
    true
  end

  def scrub(*args)
    dup
  end

  def encode(*args)
    dup
  end

  def encode!(*args)
    self
  end

  def b
    dup
  end

  # Match string against pattern
  # Delegates to pattern's =~ method
  def =~(pattern)
    return nil if pattern.nil?
    # `str =~ obj` delegates to `obj =~ str` so a Regexp (or any object defining =~) does the match.
    # But a String pattern would re-enter String#=~ forever -> infinite recursion / stack overflow.
    # MRI raises TypeError for `String =~ String`; do the same instead of recursing.
    raise TypeError.new("type mismatch: String given") if pattern.is_a?(String)
    pattern =~ self
  end

  # String#match(pattern, pos=0) -> MatchData or nil. A String pattern is treated as a Regexp source.
  def match(pattern, pos = 0)
    pattern = Regexp.new(pattern) if pattern.is_a?(String)
    return nil if pattern.nil?
    pattern.match(self, pos)
  end

  # String#match?(pattern, pos=0) -> true/false (no MatchData / no $~ side effects).
  def match?(pattern, pos = 0)
    pattern = Regexp.new(pattern) if pattern.is_a?(String)
    return false if pattern.nil?
    !pattern.match(self, pos).nil?
  end

  # String#unpack: delegates to the shared __Pack codec (lib/core/pack.rb).
  # Integer directives (C c S s L l Q q N n V v J j I i w U), string directives
  # (a A Z b B h H m u) and position directives (x X @) with <>/!/_ modifiers.
  # Float directives raise NotImplementedError until Float lands.
  def unpack(format)
    if !format.is_a?(String)
      raise TypeError, "no implicit conversion of #{format.class} into String" if !format.respond_to?(:to_str)
      format = format.to_str
    end
    __Pack.unpack(self, format)
  end

  # Return a new string with characters in reverse order
  def reverse
    result = String.new
    l = length
    i = l - 1
    while i >= 0
      result << self[i]
      i = i - 1
    end
    result
  end

  # Reverse the string in place
  # Note: This modifies the original string buffer, which only works for
  # dynamically allocated strings. String literals may be in read-only memory.
  def reverse!
    # Create a reversed copy and replace our buffer with it
    rev = self.reverse
    self.__set_raw(rev.__get_raw)
    self
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
