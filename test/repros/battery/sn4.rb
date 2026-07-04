class K2
  def initialize; @m = 0; end
  def m=(v); @m = v; end
  def m; @m; end
end
def it3; yield; end
it3 do
  obj = K2.new
  obj&.m += 3
  p obj.m
end
