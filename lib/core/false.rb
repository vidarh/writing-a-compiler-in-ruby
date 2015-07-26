
class FalseClass

  def __true?
    %s(sexp 0)
  end

  def to_s
    "false"
  end

  def inspect
    to_s
  end

  def !
    true
  end

end
