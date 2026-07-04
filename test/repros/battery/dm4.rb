class K6; end
K6.send(:define_method, :greet) do |n| "hi " + n end
o = K6.new
p o.__dispatch_missing__(:greet, "direct")
p o.greet("via-thunk")
