
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
      __track(key, nil)
      return nil
    end
    val = val.to_str
    %s(setenv (callm key __get_raw) (callm val __get_raw) 1)
    __track(key, val)
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
    __track(key, nil)
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

  def self.assoc(key)
    v = self[key]
    v.nil? ? nil : [key.to_str, v]
  end

  # --- iteration support ------------------------------------------------------
  # The C `environ` array is not directly reachable from generated code, so the
  # snapshot Hash is seeded ONCE from /proc/self/environ (NUL-separated; needs the
  # binary-safe String) and kept in sync by []=/delete/clear from then on. getenv
  # stays authoritative for single-key reads.
  def self.__snapshot
    if $__env_snapshot.nil?
      $__env_snapshot = {}
      raw = nil
      begin
        raw = IO.read("/proc/self/environ")
      rescue
        raw = nil
      end
      if raw
        raw.split(0.chr).each do |pair|
          i = pair.index("=")
          if !i.nil?
            $__env_snapshot[pair[0, i]] = pair[i + 1, pair.length]
          end
        end
      end
    end
    $__env_snapshot
  end

  def self.__track(key, val)
    snap = __snapshot
    if val.nil?
      snap.delete(key)
    else
      snap[key] = val
    end
    val
  end

  def self.to_hash
    h = {}
    __snapshot.each do |k, v|
      h[k] = v
    end
    h
  end

  def self.to_h(&block)
    h = to_hash
    return h if !block
    out = {}
    h.each do |k, v|
      pair = block.call(k, v)
      out[pair[0]] = pair[1]
    end
    out
  end

  def self.to_a
    a = []
    __snapshot.each do |k, v|
      a << [k, v]
    end
    a
  end

  def self.each(&block)
    return to_a.each if !block
    __snapshot.each do |k, v|
      block.call([k, v])
    end
    self
  end

  def self.each_pair(&block)
    each(&block)
  end

  def self.each_key(&block)
    return keys.each if !block
    keys.each do |k|
      block.call(k)
    end
    self
  end

  def self.each_value(&block)
    return values.each if !block
    values.each do |v|
      block.call(v)
    end
    self
  end

  def self.keys
    __snapshot.keys
  end

  def self.values
    __snapshot.values
  end

  def self.length
    keys.length
  end

  def self.size
    keys.length
  end

  def self.empty?
    keys.length == 0
  end

  def self.value?(v)
    values.include?(v)
  end

  def self.has_value?(v)
    values.include?(v)
  end

  def self.key(v)
    __snapshot.each do |k, val|
      return k if val == v
    end
    nil
  end

  def self.rassoc(v)
    __snapshot.each do |k, val|
      return [k, val] if val == v
    end
    nil
  end

  def self.values_at(*keys)
    keys.map { |k| self[k] }
  end

  def self.slice(*ks)
    h = {}
    ks.each do |k|
      v = self[k]
      h[k.to_str] = v if !v.nil?
    end
    h
  end

  def self.except(*ks)
    h = to_hash
    ks.each do |k|
      h.delete(k)
    end
    h
  end

  def self.invert
    h = {}
    __snapshot.each do |k, v|
      h[v] = k
    end
    h
  end

  def self.clear
    keys.each do |k|
      self.delete(k)
    end
    self
  end

  # Full replace: clear everything, then set each pair from the given hash.
  def self.replace(hash)
    keys.each do |k|
      self.delete(k) if !hash.key?(k)
    end
    hash.each do |k, v|
      self[k] = v
    end
    self
  end

  # ENV.select/filter -> Hash of the pairs the block accepts.
  def self.select(&block)
    h = {}
    __snapshot.each do |k, v|
      h[k] = v if block.call(k, v)
    end
    h
  end

  def self.filter(&block)
    select(&block)
  end

  # In-place select: keep only accepted pairs; returns ENV (nil if unchanged for select!/filter!).
  def self.keep_if(&block)
    delete_if { |k, v| !block.call(k, v) }
  end

  def self.select!(&block)
    changed = false
    to_a.each do |pair|
      if !block.call(pair[0], pair[1])
        self.delete(pair[0])
        changed = true
      end
    end
    return nil if !changed
    self
  end

  def self.filter!(&block)
    select!(&block)
  end

  def self.reject(&block)
    h = {}
    __snapshot.each do |k, v|
      h[k] = v if !block.call(k, v)
    end
    h
  end

  def self.reject!(&block)
    changed = false
    to_a.each do |pair|
      if block.call(pair[0], pair[1])
        self.delete(pair[0])
        changed = true
      end
    end
    return nil if !changed
    self
  end

  def self.delete_if(&block)
    to_a.each do |pair|
      self.delete(pair[0]) if block.call(pair[0], pair[1])
    end
    self
  end

  # ENV.merge -> Hash (does not modify ENV); ENV.update mutates ENV and returns it.
  def self.merge(*hashes, &block)
    h = to_hash
    hashes.each do |other|
      other.each do |k, v|
        if block && h.key?(k)
          h[k] = block.call(k, h[k], v)
        else
          h[k] = v
        end
      end
    end
    h
  end

  def self.update(*hashes, &block)
    hashes.each do |other|
      other.each do |k, v|
        if block && self.key?(k)
          v = block.call(k, self[k], v)
        end
        self[k] = v
      end
    end
    self
  end

  def self.merge!(*hashes, &block)
    update(*hashes, &block)
  end

  def self.filter_map(&block)
    out = []
    __snapshot.each do |k, v|
      r = block.call(k, v)
      out << r if r
    end
    out
  end

  def self.count(*args, &block)
    return keys.length if args.empty? && !block
    n = 0
    __snapshot.each do |k, v|
      if block
        n += 1 if block.call(k, v)
      else
        n += 1 if [k, v] == args[0]
      end
    end
    n
  end

  def self.any?(&block)
    return keys.length > 0 if !block
    __snapshot.each do |k, v|
      return true if block.call(k, v)
    end
    false
  end

  def self.inspect
    to_hash.inspect
  end

  def self.rehash
    nil
  end
end
