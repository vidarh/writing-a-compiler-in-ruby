
class NilClass

  def __true?
    %s(sexp 0)
  end

  def nil?
    true
  end

  def ! *args
    true
  end

  def to_s 
    ""
  end
end

