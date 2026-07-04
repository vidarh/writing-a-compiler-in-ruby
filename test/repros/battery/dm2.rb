class Yielder2
  def z; yield; end
end
class OBV
  def initialize; @y = Yielder2.new; end
  def method_missing(method, *args, &block)
    self.class.send :define_method, method do |*a, &b|
      @y.send method, *a, &b
    end
    send method, *args, &block
  end
end
o = OBV.new
p(o.z { 1 })
