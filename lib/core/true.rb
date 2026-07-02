
class TrueClass

  def !
    false
  end

  # true is an immediate; Object#singleton_class would deref the immediate as a pointer and segfault.
  # Ruby returns TrueClass (see core/kernel/singleton_class_spec).
  def singleton_class
    TrueClass
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
