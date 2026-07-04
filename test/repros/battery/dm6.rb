class K8
  def method_missing(sym, *a); [:mm, sym, a]; end
end
p K8.new.zap(1)
