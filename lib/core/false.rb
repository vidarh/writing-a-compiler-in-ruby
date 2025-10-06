
class FalseClass

  def __true?
    %s(sexp 0)
  end

  def to_s
    "false"
  end

  def inspect
    to_s
  end

  def !
    true
  end

  def dup
    self
  end

  def & other
    false
  end
end

# FIXME: MRI does not allow creating an object of FalseClass
false = FalseClass.new 
