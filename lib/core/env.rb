
class ENV
  def self.[](key)
    key = key.to_str
    %s(__get_string (getenv (callm key __get_raw)))
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
