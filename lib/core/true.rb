
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

  # NOTE: frozen? method removed - causes selftest-c crash (Issue #8)
  # TODO: Re-add when vtable size issue is fixed
  # def frozen?
  #   true
  # end

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
