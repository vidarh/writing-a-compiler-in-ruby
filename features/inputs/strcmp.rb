
a = "foo"
b = "bar"

if a == b
  puts "ERROR"
end

if a == "foo"
  puts "foo"
end

if b == "bar"
  puts "bar"
end

if a == "bar"
  puts "ERROR2"
end

if b == "foo"
  puts "ERROR3"
end
