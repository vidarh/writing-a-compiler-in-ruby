
class Delegate
end

#
# FIXME
# Very basic initial implementation
# of SimpleDelegator. Note that according to
# the docs, it is incorrect for the methods
# to change if __setobj__ is called, which
# implies forwarding methods are created,
# rather than relying on method_missing
#
class SimpleDelegator
  def initialize ob
    @ob = ob
  end

  # FIXME: Cleaner way is to remove default implementations
  def inspect
    @ob.inspect
  end

  def to_s
    @ob.to_s
  end

  def __getobj__
    @ob
  end

  def __setobj__ ob
    @ob = ob
  end

  def [] index
    @ob[index]
  end

  def respond_to?(m)
    @ob.respond_to?(m)
  end

  # ==/!=/eql?/hash are defined on Object, so method_missing never fires for them -- without explicit
  # delegation they fall back to identity, so `SimpleDelegator.new(x) == x` was FALSE self-hosted while
  # MRI's stdlib SimpleDelegator (used MRI-hosted) delegates and returns TRUE. That divergence made the
  # emitter's `movl src,dest if src != dest` self-move guard skip on MRI but not self-hosted. Delegate them.
  def ==(o)
    @ob == o
  end

  def !=(o)
    @ob != o
  end

  def eql?(o)
    @ob.eql?(o)
  end

  def hash
    @ob.hash
  end

  def method_missing *args
    @ob.send(*args)
  end
end
