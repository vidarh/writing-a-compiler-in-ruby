
class Object
  # FIXME: Should include "Kernel" here

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def respond_to?
    %s(puts "Object#respond_to not implemented")
  end

  def is_a?
    %s(puts "Object#is_a? not implemented")
  end

  def __send__ sym, *args
    %s(printf "WARNING: __send__ bypassing vtable not yet implemented. Called with %s\n" (callm sym to_s))
  end
end
