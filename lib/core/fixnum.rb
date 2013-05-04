
class Fixnum < Integer

  def + other

  end

  def - other

  end

  def <= other

  end

  def == other

  end

  def < other

  end

  def > other

  end

  def >= other

  end

  def div other
  end

  def mul other
  end

  # These two definitions are only acceptable temporarily,
  # because we will for now only deal with integers

  def * other
    mul(other)
  end

  def / other
    div(other)
  end
  
end
