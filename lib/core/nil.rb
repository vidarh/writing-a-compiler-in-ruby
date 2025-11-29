
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

  def dup
    self
  end

  # nil is always frozen
  def frozen?
    true
  end

  def to_i
    0
  end

  def to_a
    []
  end

  def to_h
    {}
  end

  def rationalize(arg=nil)
  end

  # FIXME: Stub - should raise TypeError
  def - other
    nil
  end
end

# FIXME: MRI does not allow creating an object of NilClass.
nil  = NilClass.new

# Initialize uninitialized global variables to nil
%s(__init_globals)
