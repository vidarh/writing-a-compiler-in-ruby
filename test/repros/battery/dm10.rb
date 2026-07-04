pr = proc { |*a, &b| [a, b ? b.call : :nob] }
o = Object.new
p pr.__call_with_self(o)
p(pr.__call_with_self(o, 1, 2))
blk = proc { 7 }
p pr.__call_with_self(o, &blk)
