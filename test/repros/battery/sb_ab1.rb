pr = proc { |*a, &b| [a, b ? b.call : :nob] }
p pr.call(1, 2, 3)
p(pr.call(4) { 9 })
