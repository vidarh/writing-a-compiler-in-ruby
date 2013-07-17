
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
    %s(printf "WARNING: __send__ bypassing vtable not yet implemented.\n")
    %s(printf "WARNING:    Called with %p\n" sym)
    %s(printf "WARNING:    self = %p\n" self)
    %s(if sym (printf "WARNING:    (string: '%s'\n" (callm sym to_s)))
  end

  # FIXME: Belongs in Kernel
# FIXME: Add splat support for s-expressions / call so that
# the below works
#  def printf format, *args
#    %s(printf format (rest args))
#  end

  # FIXME: Belongs in Kernel
  def puts *str
    %s(assign na (__get_fixnum numargs))
    
    if na == 2
      %s(puts "")
      return
    end
    
    %s(assign raw (index str 0))
    raw = raw.to_s.__get_raw
    %s(if raw
         (puts raw)
         (puts "")
         )
  end

  def print str
    raw = str.to_s.__get_raw
    %s(if raw
         (printf "%s" raw)
         )
  end
end
