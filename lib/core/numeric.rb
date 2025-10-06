
class Numeric
  def dup
    self
  end

  def i
    Complex.new(0,self)
  end
end
