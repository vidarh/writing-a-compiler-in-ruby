# Test for ternary operator bug (KNOWN_ISSUES.md #2)
# Problem: When condition is false, returns false instead of else value

def test_ternary_bug
  # Should return "CORRECT", but returns false
  result = false ? "WRONG" : "CORRECT"

  puts "Test: false ? 'WRONG' : 'CORRECT'"
  puts "Expected: CORRECT"
  puts "Actual: #{result.inspect}"
  puts "Pass: #{result == "CORRECT"}"
  puts

  # Test with truthy condition (should work)
  result2 = true ? "CORRECT" : "WRONG"
  puts "Test: true ? 'CORRECT' : 'WRONG'"
  puts "Expected: CORRECT"
  puts "Actual: #{result2.inspect}"
  puts "Pass: #{result2 == "CORRECT"}"
  puts

  # Test with variable
  condition = false
  scope = "SCOPE_VALUE"
  result3 = condition ? "WRONG" : scope
  puts "Test: false_var ? 'WRONG' : scope_var"
  puts "Expected: SCOPE_VALUE"
  puts "Actual: #{result3.inspect}"
  puts "Pass: #{result3 == "SCOPE_VALUE"}"
end

test_ternary_bug
