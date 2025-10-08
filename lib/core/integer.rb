
class Integer < Numeric

  def numerator
    self
  end

  def denominator
    1
  end

  def to_r
    Rational.new(self,1)
  end

  # Integer square root using Newton's method
  def self.sqrt(n)
    return 0 if n == 0
    return 1 if n < 4

    # Newton's method for integer square root
    x = n
    done = 0
    while done == 0
      x1 = (x + n / x) / 2
      if x1 >= x
        done = 1
      else
        x = x1
      end
    end
    x
  end

  # FIXME: Stub - should try to convert to Integer
  def self.try_convert(obj)
    return obj if obj.is_a?(Integer)
    if obj.respond_to?(:to_int)
      obj.to_int
    else
      nil
    end
  end

end
