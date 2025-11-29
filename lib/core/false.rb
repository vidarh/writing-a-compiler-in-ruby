
class FalseClass

  def __true?
    %s(sexp 0)
  end

  def to_s
    "false"
  end

  alias inspect to_s

  def !
    true
  end

  def dup
    self
  end

  def frozen?
    true
  end

  def & other
    false
  end

  def | other
    other.__true?
  end

  def ^ other
    other.__true?
  end

  def << other
    0
  end

  def >> other
    0
  end
end

# FIXME: MRI does not allow creating an object of FalseClass
false = FalseClass.new 
