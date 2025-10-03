require 'set'

# Test what Set.new does with various inputs
puts "Test 1: Set.new([:a, :b])"
s1 = Set.new([:a, :b])
puts s1.inspect

puts "\nTest 2: Set.new([])"
s2 = Set.new([])
puts s2.inspect

puts "\nTest 3: Set.new(:symbol) - should fail"
begin
  s3 = Set.new(:symbol)
  puts s3.inspect
rescue => e
  puts "Error: #{e}"
end

puts "\nTest 4: Set.new([[:a, :default, :nil]])"
s4 = Set.new([[:a, :default, :nil]])
puts s4.inspect
