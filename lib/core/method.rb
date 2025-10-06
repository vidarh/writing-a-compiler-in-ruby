
# FIXME: WIldly incomplete

class Method
  def initialize(target, method)
    @target = target
    @method = method
  end
  
  def owner
    @target.class
  end
end

class Object
  def method(sym)
    Method.new(self,sym)
  end
end
