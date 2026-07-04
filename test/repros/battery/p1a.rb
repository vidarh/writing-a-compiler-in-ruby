x = proc { |&b| b }
p x.call
y = proc { |&b| b.call }
p(y.call { 42 })
