
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
    if other
      true
    else
      false
    end
  end
end
