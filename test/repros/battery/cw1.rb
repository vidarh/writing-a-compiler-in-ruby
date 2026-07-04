class Proc
  def __cws_probe(newself, *rest)
    rest
  end
end
pr = proc { |*a, &b| a }
p pr.__cws_probe(1)
p pr.__cws_probe(1, 2)
p pr.call(5)
p pr.__call_with_self(nil, 5)
