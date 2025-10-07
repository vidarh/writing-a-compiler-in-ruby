
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

# FIXME: Belongs in Kernel
# FIXME: Stub - should handle base parameter and string conversion properly
def Integer(arg, base = 10)
  if arg.respond_to?(:to_int)
    arg.to_int
  elsif arg.respond_to?(:to_i)
    arg.to_i
  else
    0
  end
end
