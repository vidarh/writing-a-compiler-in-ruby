# Marshal -- ported from pure_ruby_marshal (github.com/vidarh/pure_ruby_marshal), adapted to this
# compiler. Uses the now-real dynamic-ivar reflection (instance_variables / instance_variable_get /
# instance_variable_set) plus const_get / allocate / extend that lib/core already provides. This is the
# real Marshal that replaces the temporary COREMARSHAL AST-cache bridge.
#
# Compiler adaptations (see docs/MARSHAL_REFLECTION_PLAN.md):
#  - the "\x04\b" header is built via chr (the "\b" string escape is not backspace here);
#  - integers use the fixnum varint only (the bignum 2**30 boundary + heap*heap multiply are broken);
#    'l' bignum encode/decode is stubbed until those are fixed.

module Marshal
  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  def self.dump(object, *rest)
    MarshalWriter.new.dump(object)
  end

  def self.load(data, *rest)
    MarshalReader.new(data).read
  end

  def self.restore(data, *rest)
    load(data)
  end
end

# ---- writer (dump) ---------------------------------------------------------------------------------
class MarshalWriter
  def initialize
    @ocache = {}
    @scache = {}
  end

  def dump(object)
    header = 4.chr + 8.chr   # "\x04\b" -- MAJOR 4, MINOR 8
    header + write(object)
  end

  def str(s)
    s = s.to_s
    fixnum(s.length) + s
  end

  def symbol(s)
    sym = s.to_sym
    cached = @scache[sym]
    return ";" + fixnum(cached) if cached
    @scache[sym] = @scache.length
    ":" + str(s.to_s)
  end

  def hash_body(h)
    out = fixnum(h.length)
    h.each do |k, v|
      out = out + write(k) + write(v)
    end
    out
  end

  def basic(ob)
    if ob.is_a?(Float) && ob == 0.0
      # MRI distinguishes -0.0 ("-0") from +0.0 ("0"); 1.0/-0.0 is -Infinity.
      return "f" + str("-0") if (1.0 / ob) < 0.0
      return "f" + str("0")
    end
    return "0" if ob.nil?
    return "T" if ob == true
    return "F" if ob == false
    if ob.is_a?(Integer)
      # 'i' fixnum varint only covers ~+/-2**30; larger integers use the 'l' bignum form.
      if ob >= 1073741824 || ob <= -1073741824
        return "l" + bignum(ob)
      end
      return "i" + fixnum(ob)
    end
    if ob.is_a?(Symbol)
      return symbol(ob)
    end
    if ob.is_a?(Float)
      return "f" + str("inf")  if ob == Float::INFINITY
      return "f" + str("-inf") if ob == (0.0 - Float::INFINITY)
      return "f" + str("nan")  if ob.nan?
      return "f" + str(ob.to_s)
    end
    nil
  end

  # Wrap a serialized Array/Hash payload in MRI's 'I' inline-ivars envelope when the object carries user
  # instance variables (an Array/Hash subclass with @ivars, e.g. AST::Expr < Array with @position):
  # I <payload> <ivar-count> <(:sym value)...>. A plain Array/Hash has no user ivars, so this is a no-op
  # for them (instance_variables excludes the built-in raw internals).
  def wrap_ivars(cur, body)
    ivars = cur.instance_variables
    return body if ivars.length == 0
    out = "I" + body + fixnum(ivars.length)
    i = 0
    while i < ivars.length
      nm = ivars[i]
      out = out + symbol(nm) + write(cur.instance_variable_get(nm))
      i += 1
    end
    out
  end

  def userclass(cur, klass)
    return "C" + class_sym(cur) if cur.class != klass
    ""
  end

  # Symbol for cur's class name, or a TypeError if the class is anonymous (name nil -- an anonymous
  # Class/Module/Struct or a singleton class). MRI refuses to marshal these; matching that here.
  def class_sym(cur)
    n = cur.class.name
    raise TypeError, "can't dump anonymous class" if n.nil?
    symbol(n)
  end

  def write(cur)
    v = basic(cur)
    return v if v

    key = cur.object_id
    cached = @ocache[key]
    return "@" + fixnum(cached) if cached
    @ocache[key] = @ocache.length

    if cur.is_a?(Class)
      raise TypeError, "can't dump anonymous class" if cur.name.nil?
      return "c" + str(cur.name)
    end
    if cur.is_a?(Module)
      raise TypeError, "can't dump anonymous module" if cur.name.nil?
      return "m" + str(cur.name)
    end
    if cur.is_a?(Array)
      out = userclass(cur, Array) + "[" + fixnum(cur.length)
      i = 0
      while i < cur.length
        out = out + write(cur[i])
        i += 1
      end
      return wrap_ivars(cur, out)
    end
    if cur.is_a?(Hash)
      return wrap_ivars(cur, userclass(cur, Hash) + "{" + hash_body(cur))
    end
    if cur.is_a?(Struct) || cur.is_a?(Data)
      # S <class symbol> <member=>value hash>. MRI uses 'S' for both Struct and Data. Needs the class
      # to be named (see #26).
      return "S" + class_sym(cur) + hash_body(cur.to_h)
    end
    if cur.is_a?(String)
      # A String SUBCLASS (exact String was handled in basic()): I C :Class "<bytes>" carrying the
      # encoding (:E true) AND the subclass's user ivars in one inline-ivar hash.
      uivars = cur.instance_variables
      out = "I" + userclass(cur, String) + '"' + str(cur) + fixnum(1 + uivars.length) + symbol("E") + "T"
      i = 0
      while i < uivars.length
        nm = uivars[i]
        out = out + symbol(nm) + write(cur.instance_variable_get(nm))
        i += 1
      end
      return out
    end
    if cur.respond_to?(:_dump)
      # Old-style custom serialization: klass#_dump(depth) -> a String, klass._load(str) reverses it.
      return "u" + class_sym(cur) + str(cur._dump(-1))
    end
    if cur.respond_to?(:marshal_dump)
      return "U" + class_sym(cur) + write(cur.marshal_dump)
    end
    # generic object: 'o' <class symbol> <ivar hash>
    ivars = cur.instance_variables
    out = "o" + class_sym(cur) + fixnum(ivars.length)
    i = 0
    while i < ivars.length
      nm = ivars[i]
      out = out + symbol(nm) + write(cur.instance_variable_get(nm))
      i += 1
    end
    out
  end

  # 'l' bignum: sign byte, then a fixnum count of 2-byte words, then the magnitude little-endian
  # (padded to an even byte count). Needs working bignum &/>>/abs.
  def bignum(n)
    sign = n >= 0 ? "+" : "-"
    n = n.abs
    bytes = ""
    while n > 0
      bytes = bytes + (n & 255).chr
      n = n >> 8
    end
    bytes = bytes + 0.chr if bytes.length == 0
    bytes = bytes + 0.chr if (bytes.length & 1) != 0   # pad to an even (2-byte-word) length
    words = bytes.length / 2
    sign + fixnum(words) + bytes
  end

  # Marshal variable-length signed integer encoding.
  def fixnum(n)
    return 0.chr if n == 0
    return (n + 5).chr if n > 0 && n < 123
    return (256 + n - 5).chr if n < 0 && n >= -123

    if n > 0
      bytes = ""
      while n != 0
        bytes = bytes + (n & 255).chr
        n = n >> 8
      end
      bytes.length.chr + bytes
    else
      bytes = ""
      while n != -1
        bytes = bytes + (n & 255).chr
        n = n >> 8
      end
      (256 - bytes.length).chr + bytes
    end
  end
end

# ---- reader (load) ---------------------------------------------------------------------------------
class MarshalReader
  def initialize(data)
    @data = data   # raw string; byte values via getbyte, substrings via 2-arg slice (both host-portable)
    @pos = 0
    @major = read_byte
    @minor = read_byte
    @symbols = []
    @objects = []
  end

  def read_byte
    b = @data.getbyte(@pos)
    @pos += 1
    b
  end

  def read_char
    read_byte.chr
  end

  # Read n raw bytes as a String in a SINGLE slice. The char-at-a-time `s = s + read_byte.chr` loops were
  # O(n^2) (a fresh String every char) and the dominant load allocator; a 2-arg String slice is O(n) with
  # one allocation. `String#[pos,len]` returns a substring identically MRI/self-hosted (ast_marshal relies
  # on the same), so this stays non-divergent.
  def read_bytes(n)
    s = @data[@pos, n]
    @pos += n
    s
  end

  # Dispatch on the raw tag BYTE (integer), not a 1-char String. `read` runs once per node -- millions of
  # times for a large AST -- and `read_byte.chr` was allocating a throwaway String every call, a big slice
  # of load-time GC. Integer compares are allocation-free and behave identically MRI/self-hosted.
  def read
    c = read_byte
    return nil   if c == 48    # "0"
    return true  if c == 84    # "T"
    return false if c == 70    # "F"
    return read_integer     if c == 105  # "i"
    return read_bignum      if c == 108  # "l"
    return read_module_ref  if c == 99 || c == 109  # "c" Class / "m" Module reference
    return read_symbol      if c == 58   # ":"
    return read_string      if c == 34   # '"'
    return read_ivar_tagged if c == 73   # "I" -- object with inline ivars (e.g. a String's encoding)
    return read_array       if c == 91   # "["
    return read_hash        if c == 123  # "{"
    return read_float       if c == 102  # "f"
    return read_object      if c == 111  # "o"
    return read_struct      if c == 83   # "S"
    return read_userclass   if c == 67   # "C"
    return read_load        if c == 117  # "u"
    return read_marshal_load if c == 85  # "U"
    return read_symbol_link if c == 59   # ";"
    return read_object_link if c == 64   # "@"
    raise "Marshal: unsupported type #{c.chr.inspect}"
  end

  def read_integer
    c = (read_byte ^ 128) - 128
    return 0 if c == 0
    return c - 5 if c >= 5 && c <= 127
    return c + 5 if c >= -128 && c <= -6
    if c >= 1 && c <= 4
      result = 0
      i = 0
      while i < c
        result = result | (read_byte << (8 * i))
        i += 1
      end
      return result
    end
    # c in -5..-1 : negative, (-c) bytes
    n = -c
    result = -1
    i = 0
    while i < n
      a = ~(255 << (8 * i))
      b = read_byte << (8 * i)
      result = (result & a) | b
      i += 1
    end
    result
  end

  # 'l' bignum: sign, fixnum word-count (2-byte words), then little-endian magnitude bytes.
  def read_bignum
    sign = read_char
    len = read_integer * 2
    result = 0
    i = 0
    while i < len
      result = result + (read_byte * (2 ** (i * 8)))
      i += 1
    end
    sign == "+" ? result : (0 - result)
  end

  # 'c' / 'm' <raw string name>: a reference to the named Class or Module (const_get). Registered in the
  # object table (MRI links repeated class references).
  def read_module_ref
    klass = marshal_const_get(read_bytes(read_integer))
    @objects << klass
    klass
  end

  def read_symbol
    sym = read_bytes(read_integer).to_sym
    @symbols << sym
    sym
  end

  def read_string
    s = read_bytes(read_integer)
    @objects << s
    s
  end

  def read_array
    arr = []
    @objects << arr
    n = read_integer
    i = 0
    while i < n
      arr << read
      i += 1
    end
    arr
  end

  def read_hash
    h = {}
    @objects << h
    n = read_integer
    i = 0
    while i < n
      k = read
      v = read
      h[k] = v
      i += 1
    end
    h
  end

  def read_float
    s = read_bytes(read_integer)
    @objects << s
    return Float::INFINITY if s == "inf"
    return (0.0 - Float::INFINITY) if s == "-inf"
    return (0.0 / 0.0) if s == "nan"
    s.to_f
  end

  def marshal_const_get(name)
    Object.const_get(name)
  end

  def read_object
    klass = marshal_const_get(read.to_s)
    obj = klass.allocate
    @objects << obj
    n = read_integer
    i = 0
    while i < n
      name = read       # a symbol
      value = read
      obj.instance_variable_set(name, value)
      i += 1
    end
    obj
  end

  def read_marshal_load
    klass = marshal_const_get(read.to_s)
    obj = klass.allocate
    @objects << obj
    data = read
    obj.marshal_load(data)
    obj
  end

  # 'S' <class symbol> <member=>value hash>: reconstruct the Struct with values in member order.
  def read_struct
    klass = marshal_const_get(read.to_s)
    attrs = read_hash
    members = klass.members
    values = []
    i = 0
    while i < members.length
      values << attrs[members[i]]
      i += 1
    end
    obj = klass.new(*values)
    @objects << obj
    obj
  end

  # 'C' <class symbol> <object>: a user SUBCLASS of a built-in (Array/String/Hash). Rebuild the built-in
  # payload, then re-wrap as an instance of the subclass. klass.new(data) copies an Array/String;
  # klass[data] rebuilds a Hash subclass. (Any user ivars on the subclass ride an enclosing 'I'.)
  def read_userclass
    klass = marshal_const_get(read.to_s)
    data = read
    # NOTE: MRI reconstructs an Array/String subclass by allocate + copying the payload directly (never
    # calling the subclass's initialize). Doing that here is blocked on the subclass-allocate undersizing
    # bug (task #30: `klass.allocate` on an Array subclass with added ivars under-sizes the object ->
    # heap corruption). Until that lands we keep klass.new(data); a custom initialize(*elements) can
    # mis-nest a single-Array payload, but that is contained to such subclasses.
    obj = data.is_a?(Hash) ? klass[data] : klass.new(data)
    @objects << obj
    obj
  end

  # 'u' <class symbol> <String>: reconstruct via the class method klass._load(str).
  def read_load
    klass = marshal_const_get(read.to_s)
    str = read_string
    obj = klass._load(str)
    @objects << obj
    obj
  end

  # 'I' <object> <ivar-count> <(:sym value)...>. Read the object, then apply/consume its inline ivars.
  # For a String these are the encoding markers (:E / :encoding), which are NOT real ivar slots -- their
  # names don't start with '@'. We must consume them to stay aligned, but only genuine '@name' ivars get
  # set (MRI's instance_variable_set raises on a non-'@' name like :E, which would also diverge from the
  # self-hosted runtime -- both hosts must run this identically).
  def read_ivar_tagged
    obj = read
    n = read_integer
    i = 0
    while i < n
      name = read
      value = read
      # NB: `s[0]` returns an Integer byte on the self-hosted runtime but a 1-char String under MRI, so
      # `s[0] == "@"` would DIVERGE (and silently drop every ivar self-hosted). `s[0..0]` is a String slice
      # on both hosts -- use it so the '@' guard behaves identically MRI-hosted and self-hosted.
      if name.to_s[0..0] == "@" && obj.respond_to?(:instance_variable_set)
        obj.instance_variable_set(name, value)
      end
      i += 1
    end
    obj
  end

  def read_symbol_link
    @symbols[read_integer]
  end

  def read_object_link
    @objects[read_integer]
  end
end
