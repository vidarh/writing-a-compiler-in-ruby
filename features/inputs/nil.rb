
foo = nil

puts "1: foo"
if foo
  puts "ERROR: nil"
else
  puts "OK: nil"
end

puts "2: !foo"
if !foo
  puts "OK: nil2"
else
  puts "ERROR: nil2"
end

puts "3: foo.nil?"
if foo.nil?
  puts "OK: nil?"
else
  puts "ERROR: nil?"
end

puts "4: !foo.nil?"
#FIXME:
if !(foo.nil?)
  puts "ERROR: !nil?"
else
  puts "OK: !nil?"
end

puts "5: foo = 'Blah'; if foo.nil?"
foo = "Bla"
if foo.nil?
  puts "ERROR: foo.nil?"
else
  puts "OK: foo.nil?"
end

puts "DONE"
