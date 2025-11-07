# Test for lambda.() call syntax
# Problem: .() syntax for calling lambdas is not supported

def test_lambda_call
  puts "=== Lambda Call Syntax Tests ==="
  puts

  # Works: lambda.call
  l = lambda { 42 }
  result = l.call
  puts "Test: lambda.call"
  puts "Expected: 42"
  puts "Actual: #{result}"
  puts "Pass: #{result == 42}"
  puts

  # FAILS: lambda.() syntax
  # Uncomment to see parse error:
  # l2 = lambda { 99 }
  # result2 = l2.()
  # puts "lambda.(): #{result2}"
end

test_lambda_call
