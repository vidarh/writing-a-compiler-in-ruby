
class TrueClass

  def !
    false
  end

  def to_s
    "true"
  end

  def inspect
    to_s
  end

  def == other
    %s(if (eq other true) true false)
  end

  def dup
    self
  end
end

# FIXME: MRI does not allow creating an object of TrueClass
true = TrueClass.new 
