class Y2
  def z; yield; end
end
y = Y2.new
a = []
b = proc { 5 }
p(y.send(:z, *a, &b))
