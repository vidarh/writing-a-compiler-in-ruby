def m1
  pr = proc { |&b| b ? b.call : :noblock }
  a = pr.call { :callblock }
  b = pr.call
  [a, b]
end
p m1
def m2
  inner = proc { yield }
  inner.call
end
p(m2 { :methodblock })
def m3
  pr = proc { block_given? }
  [pr.call, pr.call { :x }]
end
p(m3 { :given })
p m3
puts "done"
