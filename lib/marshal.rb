
# lib/mruby_prelude.rb

# Prelude for Mruby/DragonRuby version to polyfill Marshal
# A merged file is produced with 'rake stb' in the main directory.

module PureRubyMarshal
end

module Marshal
  def dump(ob)
    PureRubyMarshal.dump(ob)
  end

  def load(str)
    PureRubyMarshal.load(str)
  end
end

# lib/pure_ruby_marshal/read_buffer.rb
class PureRubyMarshal::ReadBuffer
  attr_reader :data, :major_version, :minor_version

  def initialize(data)
    @data = data.unpack("C*")
    @major_version = read_byte
    @minor_version = read_byte
    @symbols_cache = []
    @objects_cache = []
  end

  def read_byte
    data.shift
  end

  def read_char
    read_byte.chr
  end

  def read
    char = read_char
    case char
    when '0' then nil
    when 'T' then true
    when 'F' then false
    when 'i' then read_integer
    when 'l' then read_bignum
    when ':' then read_symbol
    when '"' then read_string
    when 'I' then read
    when '[' then read_array
    when '{' then read_hash
    when '}' then read_hash(with_default: true)
    when 'f' then read_float
    when 'c' then read_class
    when 'm' then read_module
    when 'S' then read_struct
    when '/' then read_regexp
    when 'o' then read_object
    when 'C' then read_userclass
    when 'u' then read_load
    when 'U' then read_marshal_load
    when 'e' then read_extended_object
    when ';' then read_symbol_link
    when '@' then read_object_link
    else
      raise NotImplementedError, "Unknown object type #{char}"
    end
  end

  def read_bignum
    sign = read_char
    len = read_integer * 2
    bytes = len.times.map{|i| [read_byte,i] }
    result = 0
    bytes.each do |byte, exp|
      result += (byte * 2 ** (exp * 8))
    end
    sign == "+" ? result : -result
  end
  
  def read_integer
    # c is our first byte
    c = (read_byte ^ 128) - 128

    case c
    when 0 then 0
    when (5..127)   then c - 5
    when (-128..-6) then c + 5
    when (1..4)
      c.times.map { |i| [i, read_byte] }.inject(0) { |result, (i, byte)| result | (byte << (8*i)) }
    when (-5..-1)
      (-c).times.map { |i| [i, read_byte] }.inject(-1) do |result, (i, byte)|
        a = ~(0xff << (8*i))
        b = byte << (8*i)
        (result & a) | b
      end
    end
  end

  def cache_object(&block)
    object = block.call
    @objects_cache << object
    object
  end

  def read_symbol
    symbol = read_integer.times.map { read_char }.join.to_sym
    @symbols_cache << symbol
    symbol
  end

  def read_string(cache: true)
    string = read_integer.times.map { read_char }.join
    @objects_cache << string if cache
    string
  end

  def read_array
    cache_object {
      read_integer.times.map { read }
    }
  end

  def read_hash(cache: true, with_default: false)
    Hash.new.tap do |hash|
      @objects_cache << hash if cache
      read_integer.times do
        k = read
        v = read
        hash[k]=v
      end
      hash.default = read if with_default
    end
  end

  def read_float
    # Float is not implemented in this compiler; return the raw string form.
    cache_object {
      read_string(cache: false)
    }
  end

  def marshal_const_get(const_name)
    Object.const_get(const_name)
  rescue NameError
    raise ArgumentError, "undefined class/module #{const_name}"
  end

  def read_class
    cache_object {
      const_name = read_string
      klass = marshal_const_get(const_name)
      unless klass.instance_of?(Class)
        raise ArgumentError, "#{const_name} does not refer to a Class"
      end
      klass
    }
  end

  def read_module
    cache_object {
      const_name = read_string
      klass = marshal_const_get(const_name)
      unless klass.instance_of?(Module)
        raise ArgumentError, "#{const_name} does not refer to a Module"
      end
      klass
    }
  end

  def read_struct
    cache_object {
      klass = marshal_const_get(read)
      attributes = read_hash(cache: true)
      values = attributes.values_at(*klass.members)
      klass.new(*values)
    }
  end

  def read_regexp
    # Regexp construction is unsupported here; consume the bytes and return the source string.
    cache_object {
      string = read_string
      kcode = read_byte
      string
    }
  end

  def read_load
    cache_object {
      klass = marshal_const_get(read)
      str = read_string
      klass._load(str)
    }
  end

  def read_marshal_load
    cache_object {
      klass = marshal_const_get(read)
      data = read
      object = klass.allocate
      object.marshal_load(data)
      object
    }
  end
  
  
  def read_object
    cache_object {
      klass = marshal_const_get(read)
      ivars_data = read_hash(cache: false)
      object = klass.allocate
      ivars_data.each do |ivar_name, value|
        object.instance_variable_set(ivar_name, value)
      end
      object
    }
  end

  def read_userclass
    cache_object {
      klass = marshal_const_get(read)
      data = read
      if data.is_a?(Hash)
        klass[data]
      else
        klass.new(data)
      end
    }
  end

  def read_extended_object
    cache_object {
      mod = marshal_const_get(read)
      object = read
      object.extend(mod)
    }
  end

  def read_symbol_link
    @symbols_cache[read_integer]
  end

  def read_object_link
    @objects_cache[read_integer]
  end
end

# lib/pure_ruby_marshal/version.rb
module PureRubyMarshal
  VERSION = "0.1.0"
end

# lib/pure_ruby_marshal/write_buffer.rb

module PureRubyMarshal
  class WriteBuffer

  def initialize
    @ocache, @scache = {}, {}
  end

  def dump(object)
    str = b("\x04\b") << write(object)
  end

  private

  # Mruby does not support string encodings. For Rubies that do, we want an ASCII 8-BIT string.
  def b(str)
    str.respond_to?(:b) ? str.b : str
  end

  def str(s); s=s.to_s; fixnum(s.length) << s; end
  def symbol(s); cache(";", s.to_sym, @scache) { ':' << str(s) }; end
  def hash(h)
    str = fixnum(h.length)
    h.each { |k,v| str << write(k) << write(v) }
    str
  end

  def basic(ob)
    # Float and Regexp dumping disabled: unsupported in this compiler.
    case ob
      when  nil     then '0'
      when  true    then 'T'
      when  false   then 'F'
      when  0       then "i\0"
      when  Integer
        if ob >= 2**30 || ob < -2**30
          'l'+bignum(ob)
        else
          'i'+fixnum(ob)
        end
      when  String  then '"'+str(ob)
      when  Symbol  then symbol(ob)
      else nil
    end
  end

  def userclass(cur, klass)
    cur.class != klass ? ('C' << symbol(cur.class.name)) : ''
  end
  
  def write(cur)
    v = basic(cur)
    return v if v
    cache("@", cur.object_id, @ocache) do
      case cur
      when Class  then 'c' << str(cur.name)
      when Module then 'm' << str(cur.name)
      when Struct then 'S' << symbol(cur.class.name) << hash(cur.to_h)
      when Hash
        if cur.default
          userclass(cur, Hash) << '}' << hash(cur) << write(cur.default)
        else
          userclass(cur, Hash) << '{' << hash(cur)
        end
      when Array
        userclass(cur, Array) << '[' << fixnum(cur.length) <<
        cur.map { |a| write(a) }.join("")
      else
        if cur.respond_to?(:_dump)
          'u' << symbol(cur.class.name) << str(cur._dump(-1))
        elsif cur.respond_to?(:marshal_dump)
          'U' << symbol(cur.class.name) << write(cur.marshal_dump)
        else
          'o' << symbol(cur.class.name) << hash(
            cur.instance_variables.map {|ivar|
              [ivar, cur.instance_variable_get(ivar)]
            }
          )
        end
      end
    end
  end

  def fixnum(n)
    case n
    when 0        then "\0"
    when 1...123  then (n + 5).chr
    when -123..-1 then (256 + n - 5).chr
    else
      result = ""
      while n != 0 && n != -1
        result << (n & 255).chr
        n >>= 8
      end

      l_byte = n < 0 ? 256 - result.length : result.length
      l_byte.chr + result
    end
  end

  def bignum(n)
    sign = n >= 0 ? "+" : "-"
    n = n.abs
    bytes = ""
    while n > 0
      bytes << (n&0xff).chr
      n>>=8
    end
    len = (bytes.length+1)/2
    bytes << "\0" if bytes.length < len*2
    sign+fixnum(len)+bytes
  end

  def cache(type, key, cc)
    if ol = cc[key]
      return type+fixnum(ol)
    end
    cc[key] = cc.count
    yield
  end
end
end

# lib/pure_ruby_marshal.rb




module PureRubyMarshal
  extend self

  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  def dump(object)
    WriteBuffer.new.dump(object)
  end

  def load(data)
    ReadBuffer.new(data).read
  end
end

include PureRubyMarshal
