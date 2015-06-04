
a = :foo
b = :bar
c = :foo

aid = a.object_id
bid = b.object_id
cid = c.object_id

puts a.to_s
puts b.to_s
puts c.to_s

if aid == cid
  puts "OK:   aid == cid"
else
  puts "FAIL: aid != cid"
end

if aid != bid
  puts "OK:   aid != bid"
else
  puts "FAIL: aid == bid"
end

if a == c
  puts "OK:   a == c"
else
  puts "FAIL: a != c"
end

if a != b
  puts "OK:   a != b"
else
  puts "FAIL: a == b"
end
