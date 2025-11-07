# Test for control flow as expressions bug (KNOWN_ISSUES.md #1)
# Problem: Control structures work in assignments but not in other expression contexts

def test_control_flow_expressions
  puts "=== Control Flow as Expressions Tests ==="
  puts

  # Test 1: Assignment context (should work)
  puts "Test 1: Assignment context"
  result = if true; 42; end
  puts "x = if true; 42; end"
  puts "Expected: 42"
  puts "Actual: #{result}"
  puts "Pass: #{result == 42}"
  puts

  # Test 2: Method chaining (FAILS - this is the bug)
  # Uncomment to see parse error:
  # if true; 42; end.to_s

  # Test 3: Arithmetic (FAILS)
  # Uncomment to see parse error:
  # result = (if true; 5; end) + 10

  # Test 4: Array literal (FAILS)
  # Uncomment to see parse error:
  # arr = [if true; 1; end, 2]

  # Test 5: Method arguments (FAILS)
  # Uncomment to see parse error:
  # puts(if true; "yes"; end)

  # Test 6: case expression (WORKS - case is special-cased)
  puts "Test 6: case expression with method chaining"
  result = case 1
  when 1 then "one"
  when 2 then "two"
  end.upcase
  puts "case...end.upcase"
  puts "Expected: ONE"
  puts "Actual: #{result}"
  puts "Pass: #{result == "ONE"}"
end

test_control_flow_expressions
