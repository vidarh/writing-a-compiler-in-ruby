
class FalseClass

  def __true?
    %s(sexp 0)
  end

  def to_s
    "false"
  end

  def ! *args
    # FIXME: true is a keyword
    true
  end

end
