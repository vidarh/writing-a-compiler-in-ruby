require 'set'

# Test Set.new in a lambda
f = lambda do |params|
  s = Set.new(params)
  puts s.inspect
end

f.call([:a, :b, :c])
