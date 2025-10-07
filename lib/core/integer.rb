
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

end
