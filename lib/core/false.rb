
class FalseClass

  # Truthiness predicate (see Object#__true?). Must return the Ruby `false` object, not a raw 0:
  # the result flows out through FalseClass#|/#^ and TrueClass#&/#^ as an ordinary value, and a
  # raw 0 there is not a valid object pointer (calling any method on it segfaults).
  def __true?
    false
  end

  # false is an immediate; Object#singleton_class would deref the immediate as a pointer and segfault.
  # Ruby returns FalseClass (see core/kernel/singleton_class_spec).
  def singleton_class
    FalseClass
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
