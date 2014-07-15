
a = false
b = true

if a && b
   puts "ERROR: a && b == false"
else
   puts "OK: a && b == false"
end

if a || b
   puts "OK: a || b == true"
else
   puts "ERROR: a || b == true"
end

if b && a
   puts "ERROR: b && a == false"
else
   puts "OK: b && a == false"
end
