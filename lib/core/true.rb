
class TrueClass

  def ! x # FIXME: Why is it called with an argument?
    false
  end

  def == other
    if other
      true
    else
      false
    end
  end
end
