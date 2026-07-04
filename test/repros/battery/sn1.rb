class K
  attr_accessor :m
  def initialize; @m = 0; end
end
obj = K.new
obj&.m += 3
p obj.m
obj = nil
p (obj&.m += 3)
