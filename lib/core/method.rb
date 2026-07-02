
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

  # Invoked when a Method is passed as the block to instance_exec/instance_eval/class_eval etc.
  # (`obj.instance_exec(&some_method)`). Unlike a Proc, a bound Method keeps its own receiver, so the
  # rebinding `newself` is ignored -- we just call the method on @target. Mirrors MRI, where
  # `3.instance_exec(4, &5.method(:+))` == `5 + 4` == 9 (the 3 is not used).
  def __call_with_self(newself, *args, &block)
    call(*args, &block)
  end

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

  # Detach this method from its receiver, yielding an UnboundMethod.
  def unbind
    UnboundMethod.new(@target.class, @method)
  end
end

# A method detached from any receiver (Module#instance_method / Method#unbind). It carries the owner
# module/class and the method name; #bind re-attaches it to a compatible object to get a callable Method.
class UnboundMethod
  def initialize(owner, name)
    @owner = owner
    @name = name
  end

  def name
    @name
  end

  def owner
    @owner
  end

  # Bind to a receiver, returning a callable Method.
  def bind(obj)
    Method.new(obj, @name)
  end

  # Bind and immediately call (Ruby 2.7+ UnboundMethod#bind_call).
  def bind_call(obj, *args)
    obj.send(@name, *args)
  end
end

class Object
  def method(sym)
    Method.new(self,sym)
  end
end
