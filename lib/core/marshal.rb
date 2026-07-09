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
    return "f" + str("0") if ob.is_a?(Float) && ob == 0.0
    return "0" if ob.nil?
    return "T" if ob == true
    return "F" if ob == false
    if ob.is_a?(Integer)
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
    return "C" + symbol(cur.class.name) if cur.class != klass
    ""
  end

  def write(cur)
    v = basic(cur)
    return v if v

    key = cur.object_id
    cached = @ocache[key]
    return "@" + fixnum(cached) if cached
    @ocache[key] = @ocache.length

    if cur.is_a?(Class)
      return "c" + str(cur.name)
    end
    if cur.is_a?(Module)
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
      return "u" + symbol(cur.class.name) + str(cur._dump(-1))
    end
    if cur.respond_to?(:marshal_dump)
      return "U" + symbol(cur.class.name) + write(cur.marshal_dump)
    end
    # generic object: 'o' <class symbol> <ivar hash>
    ivars = cur.instance_variables
    out = "o" + symbol(cur.class.name) + fixnum(ivars.length)
    i = 0
    while i < ivars.length
      nm = ivars[i]
      out = out + symbol(nm) + write(cur.instance_variable_get(nm))
      i += 1
    end
    out
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
    @data = data.unpack("C*")
    @pos = 0
    @major = read_byte
    @minor = read_byte
    @symbols = []
    @objects = []
  end

  def read_byte
    b = @data[@pos]
    @pos += 1
    b
  end

  def read_char
    read_byte.chr
  end

  def read
    char = read_char
    return nil   if char == "0"
    return true  if char == "T"
    return false if char == "F"
    return read_integer if char == "i"
    return read_symbol  if char == ":"
    return read_string  if char == '"'
    return read_ivar_tagged if char == "I"   # object with inline ivars (e.g. a String's encoding)
    return read_array   if char == "["
    return read_hash    if char == "{"
    return read_float   if char == "f"
    return read_object  if char == "o"
    return read_userclass if char == "C"
    return read_load    if char == "u"
    return read_marshal_load if char == "U"
    return read_symbol_link  if char == ";"
    return read_object_link  if char == "@"
    raise "Marshal: unsupported type #{char.inspect}"
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

  def read_symbol
    n = read_integer
    s = ""
    i = 0
    while i < n
      s = s + read_char
      i += 1
    end
    sym = s.to_sym
    @symbols << sym
    sym
  end

  def read_string
    n = read_integer
    s = ""
    i = 0
    while i < n
      s = s + read_char
      i += 1
    end
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
    n = read_integer
    s = ""
    i = 0
    while i < n
      s = s + read_char
      i += 1
    end
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

  # 'C' <class symbol> <object>: a user SUBCLASS of a built-in (Array/String/Hash). Rebuild the built-in
  # payload, then re-wrap as an instance of the subclass. klass.new(data) copies an Array/String;
  # klass[data] rebuilds a Hash subclass. (Any user ivars on the subclass ride an enclosing 'I'.)
  def read_userclass
    klass = marshal_const_get(read.to_s)
    data = read
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
  # For a String these are the encoding markers (:E / :encoding), which are not real ivar slots here, so
  # instance_variable_set is a harmless no-op -- the point is to CONSUME them so the stream stays aligned.
  def read_ivar_tagged
    obj = read
    n = read_integer
    i = 0
    while i < n
      name = read
      value = read
      obj.instance_variable_set(name, value) if obj.respond_to?(:instance_variable_set)
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
