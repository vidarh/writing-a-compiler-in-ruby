
class NilClass

  def __true?
    %s(sexp 0)
  end

  def == other
    return !other.nil?
  end

  def nil?
    true
  end

  def !
    true
  end

  def to_s 
    ""
  end

  def inspect
    "nil"
  end
end

