class K9b
  def initialize; @m = nil; end
  def m; @m; end
  def m=(v); @m = v; end
end
o = K9b.new
p (o&.m ||= 5)
p o.m
o2 = K9b.new
o2.m = 1
p (o2&.m ||= 9)
p (o2&.m &&= 4)
p o2.m
