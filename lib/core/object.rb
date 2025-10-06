
class Object
  # At this point we have a "fixup to make as part of bootstrapping:
  #
  #  Class was created *before* Object existed, which means it is not linked into the
  #  subclasses array. As a result, unless we do this, Class will not inherit methods
  #  that are subsquently added to Object below. This *must* be the first thing to happen
  #  in Object, before defining any methods etc:
  #
  %s(assign (index self 4) Class)

  include Kernel

  def initialize
    # Default. Empty on purpose
  end

  def class
    @__class__
  end

  def object_id
    %s(__int self)
  end

  def hash
    object_id
  end

  def eql? other
    self.==(other)
  end

  def === other
    self.==(other)
  end

  def equal?(other)
    object_id == other.object_id
  end

  def inspect
    %s(assign buf (__alloc_leaf 20))
    %s(snprintf buf 20 "%p" self)
    %s(assign buf (__get_string buf))
    "#<#{self.class.name}:#{buf}>"
  end

  def to_s
    inspect
  end

  def == other
    object_id == other.object_id
  end

  def !
    false
  end

  def != other
    !(self == other)
  end

  def nil?
    false
  end

  def method_missing (sym, *args)
    cname = self.class.inspect
    puts "Method missing #{cname}##{sym.to_s}"
    %s(div 0 0)
  end

  def respond_to?(method)
    # The vtable thunks make up a contiguous sequence of memory,
    # bounded by __vtable_thunks_start and __vtable_thunks_end
    m = Class.method_to_voff

    voff = m[method]
    return false if !voff # FIXME: Handle dynamically added.

    c = self.class
    %s(assign raw (callm voff __get_raw))
    %s(assign ptr (index c raw))
    %s(if (lt ptr __vtable_thunks_start) (return true))
    %s(if (gt ptr __vtable_thunks_end) (return true))
    return false
  end

  # Relying on s-exps here to prevent bootstrap issues
  # w/Fixnum#== / Fixnum#!= which again is relied on by
  # the basic Object#object_id. Perhaps replace those
  # instead
  #
  # FIXME: This will not handle eigenclasses correctly.
  def is_a?(c)
    %s(assign k (callm self class))
    %s(while (and (ne k c) (ne k Object)) (do
      (assign k (callm k superclass))
     ))

    %s(if (eq k c) (return true) (return false))
  end

  # FIXME: A proper alias would be more efficient,
  # but not yet supported
  def kind_of?(c)
    is_a?(c)
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
    ob
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
        raw = raw.to_s
        last = raw[-1]
        raw = raw.__get_raw
        %s(if (ne raw 0) (printf "%s" raw))
        if last.ord != 10
           %s(puts "")
        end
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

  # FIXME: Belongs in Kernel
  def Array(arg)
    if arg.respond_to?(:to_ary)
      arg.to_ary
    elsif arg.respond_to?(:to_a)
      arg.to_a
    else
      [arg]
    end
  end

  def dup
    # FIXME
    self.class.new
  end
end
