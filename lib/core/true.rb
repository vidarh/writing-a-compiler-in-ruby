
class TrueClass

  def !
    false
  end

  def to_s
    "true"
  end

  def == other
    if other
      true
    else
      false
    end
  end
end
