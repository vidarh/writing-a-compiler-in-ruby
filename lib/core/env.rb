
class ENV
  def self.[](key)
    key = key.to_str
    # getenv returns NULL for an unset variable; __get_string(NULL) segfaulted. Return nil instead.
    %s(assign raw (getenv (callm key __get_raw)))
    %s(if (eq raw 0) (return nil))
    %s(__get_string raw)
  end

  def self.[]=(key,val)
  end

  def self.assoc(val)
  end

  def self.to_hash
    {}
  end

  def self.rehash
    nil
  end
end
