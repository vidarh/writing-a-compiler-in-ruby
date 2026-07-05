#
# FIXME: Breaks if you try to insert same key twice
#
class Hash

  # Hash[...] constructor. Forms:
  #   Hash[k1, v1, k2, v2, ...]   -- flat key/value list (even count; odd -> ArgumentError)
  #   Hash[{...}]                 -- a single Hash (or #to_hash-able) is copied
  #   Hash[[[k,v], [k], ...]]     -- a single Array (or #to_ary-able) of 1/2-element pair arrays
  # Uses self.new so subclasses (MyHash[...]) return their own type. Previously this hard-exited on an
  # odd arg count (aborting the whole spec run) and mishandled the single-array form (count 1 -> odd).
  def self.[] *args
    h = self.new
    len = args.length

    if len == 1
      arg = args[0]
      if arg.is_a?(Hash)
        arg.each { |k, v| h[k] = v }
        return h
      end
      if !arg.is_a?(Array) && arg.respond_to?(:to_hash)
        arg.to_hash.each { |k, v| h[k] = v }
        return h
      end
      pairs = nil
      if arg.is_a?(Array)
        pairs = arg
      elsif arg.respond_to?(:to_ary)
        pairs = arg.to_ary
      end
      if !pairs.nil?
        pairs.each do |pair|
          if !pair.is_a?(Array)
            raise ArgumentError.new("wrong element type (expected array)")
          end
          plen = pair.length
          if plen < 1 || plen > 2
            raise ArgumentError.new("invalid number of elements (#{plen} for 1..2)")
          end
          h[pair[0]] = pair[1]
        end
        return h
      end
      # A lone scalar that is neither a Hash nor an Array falls through to the odd-count check below.
    end

    if (len % 2) == 1
      raise ArgumentError.new("odd number of arguments for Hash")
    end

    pos = 0
    while pos < len
      h[args[pos]] = args[pos+1]
      pos = pos + 2
    end

    h
  end

  def sort_by
    to_a.sort_by {|pair| yield(pair[0], pair[1]) }
  end

  # Delegate to Hash#map (defined in hash.rb). The previous body `to_a.collect` dropped the block and
  # returned a bare Enumerator, so `h.collect {|k,v| ... }` never mapped.
  def collect(&block)
    map(&block)
  end
  def inspect
    # Cycle guard: a self-referential hash (h[:k]=h) would recurse forever through v.inspect ->
    # segfault. MRI prints "{...}" for a hash already being inspected. Track with a per-hash flag.
    if @__inspecting
      return "{...}"
    end
    @__inspecting = true
    str = "{"
    first = true
    each do |k,v|
      if !first
        str += ", "
      else
        first = false
      end
      str += k.inspect
      str += "=>"
      str += v.inspect
    end
    str += "}"
    @__inspecting = false
    str
  end


  def keys
    a = []
    each do |k,v|
      a << k
    end
    a
  end

  def values
    a = []
    each do |k,v|
      a << v
    end
    a
  end

  def has_key?(key)
    # Delegate to member?, which handles a nil key (whose slot stores nil and so can't be
    # distinguished from an empty slot by a truthiness check).
    member?(key)
  end

  alias key? has_key?

  def has_value?(value)
    each do |k,v|
      return true if v == value
    end
    false
  end

  alias value? has_value?

end
