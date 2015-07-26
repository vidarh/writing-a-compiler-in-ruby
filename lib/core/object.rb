
class Object
  # At this point we have a "fixup to make as part of bootstrapping:
  #
  #  Class was created *before* Object existed, which means it is not linked into the
  #  subclasses array. As a result, unless we do this, Class will not inherit methods
  #  that are subsquently added to Object below. This *must* be the first thing to happen
  #  in Object, before defining any methods etc:
  #
  %s(assign (index self 4) Class)

  # FIXME: Should include "Kernel" here

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def object_id
    %s(__get_fixnum self)
  end

  def inspect
    %s(assign buf (malloc 20))
    %s(snprintf buf 20 "%p" self)
    %s(assign buf (__get_string buf))
    "#<#{self.class.name}:#{buf}>"
  end

  def == other
    object_id == other.object_id
  end

  def != other
    !(self == other)
  end

  def nil?
    false
  end

  def respond_to?(method)
    # FIXME: respond_to? is a bit tricky:
    # Because we use thunks for method_missing, we can't just check
    # the vtable. One approach is to "tag" the start of the thunk
    # with a magic value to indicate if it's a method_missing thunk,
    # maybe.
    puts "Object#respond_to? not implemented [#{method.to_s}]"
  end

  # FIXME: This will not handle eigenclasses correctly.
  def is_a?(c)
    k = self.class
    while k != c && k != Object
      k = k.superclass
    end

    return (k == c)
  end

  # FIXME: Private
  def send sym, *args
    __send__(sym, *args)
  end

  def __send__ sym, *args
    self.class.__send_for_obj__(self,sym,*args)
  end

  # FIXME: Belongs in Kernel
# FIXME: Add splat support for s-expressions / call so that
# the below works
#  def printf format, *args
#    %s(printf format (rest args))
#  end

  def p ob
    puts ob.inspect
  end

  # FIXME: Belongs in Kernel
  def exit(code)
    %s(exit (callm code __get_raw))
  end

  # FIXME: Belongs in Kernel
  def puts *str
    na = str.length
    if na == 0
      %s(puts "")
      return
    end

    i = 0
    while i < na
      raw = str[i]
      if raw
        raw = raw.to_s.__get_raw
        %s(if (ne raw 0) (puts raw))
      else
        %s(puts "")
      end
      i = i + 1
    end
    nil
  end

  def print *str
    na = str.length
    
    if na == 0
      %s(printf "nil")
      return
    end

    i = 0
    while i < na
      raw = str[i].to_s.__get_raw
      if raw
        %s(printf "%s" raw)
      end
      i = i + 1
    end
  end
end
