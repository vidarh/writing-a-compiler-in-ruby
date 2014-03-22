
class Object
  # FIXME: Should include "Kernel" here

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def inspect
    %s(assign buf (malloc 20))
    %s(snprintf buf 20 "%p" self)
    %s(assign buf (__get_string buf))
    "#<#{self.class.name}:#{buf}>"
  end

  def respond_to?
    puts "Object#respond_to not implemented"
  end

  def is_a?(c)
    false
  end

  def __send__ sym, *args
    %s(printf "WARNING: __send__ bypassing vtable (name not statically known at compile time) not yet implemented.\n")
    %s(if sym (printf "WARNING:    Method: '%s'\n" (callm (callm sym to_s) __get_raw)))
    %s(printf "WARNING:    symbol address = %p\n" sym)
    %s(printf "WARNING:    self = %p\n" self)
    %s(printf "WARNING:    class '%s'\n" (callm (callm (callm self class) name) __get_raw))
  end

  def true
    # Note that the *value* does not matter here. All objects are truth-y, So until we 
    # sort out a proper TrueClass, this is better than nothing
    "true" 
   end

  def false
    %s(sexp 0)
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

    na = na - 2
    i = 0
    while i < na
      %s(assign raw (index str (callm i __get_raw)))
      if raw
        raw = raw.to_s.__get_raw
        %s(if raw (puts raw))
      else
        puts
      end
      i = i + 1
    end
  end

  def print *str
    %s(assign na (__get_fixnum numargs))
    
    if na == 2
      %s(printf "nil")
      return
    end

    na = na - 2
    i = 0
    while i < na
      %s(assign raw (index str (callm i __get_raw)))
      raw = raw.to_s.__get_raw
      %s(if raw (printf "%s" raw))
      i = i + 1
    end
  end
end
