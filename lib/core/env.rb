
class ENV
  def self.[](key)
    key = key.to_str
    # getenv returns NULL for an unset variable; __get_string(NULL) segfaulted. Return nil instead.
    %s(assign raw (getenv (callm key __get_raw)))
    %s(if (eq raw 0) (return nil))
    %s(__get_string raw)
  end

  def self.[]=(key,val)
    key = key.to_str
    if val.nil?
      %s(unsetenv (callm key __get_raw))
      return nil
    end
    val = val.to_str
    %s(setenv (callm key __get_raw) (callm val __get_raw) 1)
    val
  end

  def self.store(key, val)
    self[key] = val
  end

  # Delete a variable, returning its previous value (nil if it was unset). With a block, yields the key
  # when it is absent (Ruby's ENV.delete(name){|k| ...}).
  def self.delete(key)
    key = key.to_str
    old = self[key]
    if old.nil?
      return yield(key) if block_given?
      return nil
    end
    %s(unsetenv (callm key __get_raw))
    old
  end

  def self.key?(key)
    !self[key].nil?
  end

  def self.has_key?(key)
    !self[key].nil?
  end

  def self.include?(key)
    !self[key].nil?
  end

  def self.member?(key)
    !self[key].nil?
  end

  # fetch(key) / fetch(key, default) / fetch(key){|k| }. Raises KeyError when absent with no fallback.
  def self.fetch(key, *rest)
    v = self[key]
    return v if !v.nil?
    return yield(key) if block_given?
    return rest[0] if rest.length > 0
    raise KeyError.new("key not found: #{key.inspect}")
  end

  # Best-effort: set each pair from the given hash. (A full replace would also clear variables not in
  # the hash, which needs iterating the C environ -- not done yet, but this avoids a NoMethodError.)
  def self.replace(hash)
    hash.each do |k, v|
      self[k] = v
    end
    self
  end

  def self.assoc(key)
    v = self[key]
    v.nil? ? nil : [key.to_str, v]
  end

  def self.to_hash
    {}
  end

  def self.rehash
    nil
  end
end
