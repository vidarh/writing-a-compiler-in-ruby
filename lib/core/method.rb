
# FIXME: WIldly incomplete

class Method
  def initialize(target, method)
    @target = target
    @method = method
  end

  def owner
    @target.class
  end

  # Invoke the bound method on its receiver.
  def call(*args)
    @target.send(@method, *args)
  end

  alias [] call

  # Method#=== invokes the method (so a Method can be used as a case/when condition).
  def ===(arg)
    @target.send(@method, arg)
  end

  def name
    @method
  end

  def receiver
    @target
  end

  def to_proc
    m = self
    proc {|*args| m.call(*args) }
  end
end

class Object
  def method(sym)
    Method.new(self,sym)
  end
end
