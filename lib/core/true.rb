
class TrueClass

  def !
    false
  end

  def to_s
    "true"
  end

  alias inspect to_s

  def == other
    %s(if (eq other true) true false)
  end

  def dup
    self
  end

  def frozen?
    true
  end

  def & other
    other.__true?
  end

  def | other
    true
  end

  def ^ other
    !other.__true?
  end

  def << other
    1 << other
  end

  def >> other
    1 >> other
  end
end

# FIXME: MRI does not allow creating an object of TrueClass
true = TrueClass.new 
