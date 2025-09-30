
class NilClass

  def __true?
    %s(sexp 0)
  end

  def == other
    return other.nil?
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

# FIXME: MRI does not allow creating an object of NilClass.
nil  = NilClass.new

# Initialize uninitialized global variables to nil
%s(__init_globals)
