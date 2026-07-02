
class NilClass

  # Truthiness predicate (see Object#__true?). Must return the Ruby `false` object, not a raw 0:
  # the result flows out through FalseClass#|/#^ and TrueClass#&/#^ as an ordinary value, and a
  # raw 0 there is not a valid object pointer (calling any method on it segfaults).
  def __true?
    false
  end

  # nil is an immediate (no heap object), so the inherited Object#singleton_class -- which does
  # `(index self 0)` -- would dereference the immediate value as a pointer and segfault
  # (core/kernel/singleton_class_spec). Ruby returns NilClass here.
  def singleton_class
    NilClass
  end

  def == other
    return other.nil?
  end

  # Boolean operators: nil behaves like false. `&` is always false; `|` and `^` are true iff the
  # other operand is truthy (nil ^ x == nil | x because nil is falsy). Mirrors FalseClass.
  def & other
    false
  end

  def | other
    other.__true?
  end

  def ^ other
    other.__true?
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
