
class Object
  # FIXME: Should include "Kernel" here

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def respond_to?
    puts "Object#respond_to not implemented"
  end

  def is_a?
    puts "Object#is_a? not implemented"
  end

  def __send__ sym, *args
    %s(printf "WARNING: __send__ bypassing vtable not yet implemented. Called with %s\n" (callm sym to_s))
  end

  # FIXME: Belongs in Kernel
# FIXME: Add splat support for s-expressions / call so that
# the below works
#  def printf format, *args
#    %s(printf format (rest args))
#  end

  # FIXME: Belongs in Kernel
  def puts str
    %s(puts (callm str __get_raw))
  end
end
