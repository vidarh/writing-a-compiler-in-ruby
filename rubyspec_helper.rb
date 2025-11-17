# rubyspec_helper.rb
# Minimal MSpec-compatible implementation for compiling rubyspec tests

# Stub for MSpecScript - used by some specs but doesn't need actual functionality
class MSpecScript
end

$spec_passed = 0
$spec_failed = 0
$spec_skipped = 0
$spec_assertions = 0
$spec_descriptions = []
$shared_examples = {}
$spec_method = nil
$before_each_blocks = []
$after_each_blocks = []

# Minimal stub for mspec framework class needed by specs
class ScratchPad
  def self.record(value)
    @recorded = value
  end

  def self.recorded
    @recorded
  end

  def self.clear
    @recorded = nil
  end

  def self.<<(value)
    @recorded = [] if @recorded == nil
    @recorded << value
  end
end

# Stub for SpecEvaluate - used in some specs to annotate test context
# Just provides a settable desc attribute
class SpecEvaluate
  def self.desc=(value)
    @desc = value
  end

  def self.desc
    @desc
  end
end

# Tolerance for floating point comparisons
TOLERANCE = 0.00001

# CODE_LOADING_DIR - path to fixtures/code directory for file loading specs
# Simplified version without realpath support (since File.realpath may not be implemented)
CODE_LOADING_DIR = "rubyspec/fixtures/code"

def describe(description, options = nil, &block)
  # Handle hash options or block
  if options && options.is_a?(Hash) && options[:shared]
    # Store shared example block for later use
    $shared_examples[description] = block
  elsif options && !options.is_a?(Hash)
    # Old-style: description is actually the parent, options is the real description
    # This handles: describe String, "#method" do
    # For now, treat it as normal describe
    $spec_descriptions.push(options)
    puts options
    block.call
    $spec_descriptions.pop
  else
    $spec_descriptions.push(description)
    puts description
    block.call
    $spec_descriptions.pop
  end
end

def it(description, &block)
  skipped_before = $spec_skipped
  assertions_before = $spec_assertions

  # Track whether this specific test had any assertion failures
  $current_test_has_failure = false

  # Run before :each blocks
  i = 0
  while i < $before_each_blocks.length
    $before_each_blocks[i].call
    i = i + 1
  end

  # Wrap block.call in begin/rescue to catch unhandled exceptions
  begin
    block.call
  rescue => e
    $current_test_has_failure = true
    $spec_failed = $spec_failed + 1
    puts "    \e[31mFAILED: Unhandled exception: #{e.to_s}\e[0m"
  end

  if $spec_skipped > skipped_before
    puts "\e[33m  - #{description} [P:#{$spec_passed} F:#{$spec_failed} S:#{$spec_skipped}]\e[0m"
  elsif $current_test_has_failure
    # This test had assertion failures - count it as 1 failed test
    $spec_failed = $spec_failed + 1
    puts "\e[31m  ✗ #{description} [P:#{$spec_passed} F:#{$spec_failed} S:#{$spec_skipped}]\e[0m"
  else
    # Check if any assertions were actually executed
    if $spec_assertions == assertions_before
      # No assertions were made - mark as skipped
      $spec_skipped = $spec_skipped + 1
      puts "\e[33m  - #{description} (NO ASSERTIONS) [P:#{$spec_passed} F:#{$spec_failed} S:#{$spec_skipped}]\e[0m"
    else
      $spec_passed = $spec_passed + 1
      puts "\e[32m  ✓ #{description} [P:#{$spec_passed} F:#{$spec_failed} S:#{$spec_skipped}]\e[0m"
    end
  end
end

class Mock
  def initialize(name)
    @name = name
    @expectations = {}
    @call_counts = {}
    @current_method = nil
    @current_return_value = nil
  end

  # Track which method we're setting up an expectation for
  def should_receive(method)
    @current_method = method
    @call_counts[method] = 0
    self
  end

  # FIXME: Stub - should verify method is never called
  def should_not_receive(method)
    @current_method = method
    self
  end

  # FIXME: Need to track/enforce
  def any_number_of_times
    self
  end

  # FIXME: Stub - should validate exact number of calls
  def exactly(count)
    self
  end

  # FIXME: Stub - should validate at least this many calls
  def at_least(count)
    self
  end

  # FIXME: Stub - should validate at most this many calls
  def at_most(count)
    self
  end

  # FIXME: Stub - used with exactly to specify times
  def times
    self
  end

  # Store the return value(s) for the current method
  # Can accept multiple values for sequential returns
  def and_return(*results)
    if @current_method
      if results.length == 1
        @expectations[@current_method] = results[0]
      else
        @expectations[@current_method] = results
      end
    end
    self
  end

  # FIXME: Need to track/enforce - should actually raise the error
  # Since we can't raise exceptions, return nil to avoid crashes
  def and_raise(error)
    if @current_method
      @expectations[@current_method] = [:raise, error]
    end
    self
  end

  # FIXME: Stub - should validate arguments match expectations
  def with(*args)
    self
  end

  # Handle method calls dynamically
  def method_missing(method, *args)
    if @expectations[method]
      result = @expectations[method]
      # Check if this is a raise expectation
      if result.is_a?(Array) && result.length == 2 && result[0] == :raise
        # Raise the specified exception
        error_class = result[1]
        if error_class.is_a?(Class)
          raise error_class.new
        else
          raise error_class
        end
      else
        # Just return the result directly
        # NOTE: If result is an array, we return the array (not sequential values)
        # To return sequential values, use and_return(val1, val2, ...) which stores
        # them as an array in @expectations
        result
      end
    else
      STDERR.puts("Mock: No expectation set for #{method}")
      nil
    end
  end

  # Say we respond to any method if an expectation is set
  def respond_to?(method)
    # Only return true if we have an expectation set for this method
    # This prevents Integer operators from trying to call methods that don't exist
    @expectations[method] ? true : false
  end

  def to_s
    @name
  end

  # FIXME: Stub - return 0 for integer conversion
  def to_i
    0
  end

  # Override == to use expectations instead of Object#== (which compares object_id)
  # This is necessary because Object defines ==, which would be called before method_missing
  def == other
    if @expectations[:==]
      result = @expectations[:==]
      # Support arrays of return values for sequential calls
      if result.is_a?(Array) && result.length > 1 && result[0] != :raise
        # Get next return value and rotate array
        @call_counts[:==] = 0 if @call_counts[:==].nil?
        index = @call_counts[:==]
        @call_counts[:==] = @call_counts[:==] + 1
        return result[index] if index < result.length
        return result[result.length - 1]  # Return last value if we've exhausted the array
      else
        return result
      end
    else
      # No expectation set, fall back to object identity (Object#== behavior)
      return object_id == other.object_id
    end
  end

  # FIXME: Stub - used by some specs to stub out methods
  # Should actually override the method behavior on this mock
  def stub!(method_name)
    @current_method = method_name
    self
  end

  # FIXME: WORKAROUND for missing type coercion in bitwise operators
  # Bitwise operators (&, |, ^) call __get_raw directly without checking type
  # or calling to_int first. This masks the real bug that operators should
  # coerce arguments before operating on them.
  # Affected test cases:
  #   - allbits_spec.rb: "coerces the rhs using to_int" (line 23-27)
  #   - anybits_spec.rb: "coerces the rhs using to_int"
  #   - nobits_spec.rb: "coerces the rhs using to_int"
  # Without this, these tests crash with "Method missing Mock#__get_raw"
  # Real fix: Operators should call to_int/coerce before __get_raw
  def __get_raw
    0
  end
end

def mock(name)
  Mock.new(name)
end


# Matcher infrastructure
class Matcher
  def initialize(expected)
    @expected = expected
  end

  def expected
    @expected
  end
end

class EqualMatcher < Matcher
  def match?(actual)
    actual == @expected
  end


  def failure_message(actual)
    "Expected #{@expected.inspect}, got #{actual.inspect}"
  end
end

class InstanceOfMatcher < Matcher
  def match?(actual)
    actual.is_a?(@expected)
  end


  def failure_message(actual)
    "Expected instance of #{@expected.inspect}, got #{actual.inspect}"
  end
end

class BeTrueMatcher
  def match?(actual)
    if actual == true
      return true
    else
      return false
    end
  end

  def failure_message(actual)
    "Expected true, got #{actual.inspect}"
  end

  def expected
    "true"
  end
end

class BeFalseMatcher
  def match?(actual)
    actual == false
  end

  def failure_message(actual)
    "Expected false, got #{actual.inspect}"
  end

  def expected
    "false"
  end
end

class BeNilMatcher
  def match?(actual)
    actual == nil
  end

  def failure_message(actual)
    "Expected nil, got #{actual.inspect}"
  end

  def expected
    "nil"
  end
end

class EqualObjectMatcher < Matcher
  def match?(actual)
    actual.equal?(@expected)
  end

  def failure_message(actual)
    "Expected #{@expected.inspect} (object_id: #{@expected.object_id}), got #{actual.inspect} (object_id: #{actual.object_id})"
  end
end

class RaiseErrorMatcher < Matcher
  def initialize(exception, pattern = nil)
    @exception = exception
    @pattern = pattern
    @caught_exception = nil
  end

  def match?(actual)
    # Now that exceptions work, actually catch and verify them
    if actual.is_a?(Proc)
      raised = false
      @caught_exception = nil
      begin
        actual.call
      rescue => e
        raised = true
        @caught_exception = e
      end

      if raised
        if @exception
          return check_exception_type
        else
          return true
        end
      else
        return false
      end
    end

    # Not a proc, can't test
    false
  end

  def check_exception_type
    # Check if the caught exception matches the expected type
    if @caught_exception
      return @caught_exception.class.name == @exception.name
    end
    false
  end

  def failure_message(actual)
    if @exception
      "Expected #{@exception.name} to be raised but nothing was raised"
    else
      "Expected an exception to be raised but nothing was raised"
    end
  end
end

# Proxy for chained matchers like obj.should.frozen?
class ShouldProxy
  def initialize(target)
    @target = target
  end

  def ==(expected)
    $spec_assertions = $spec_assertions + 1
    result = @target == expected
    if result
    else
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected #{expected.inspect} but got #{@target.inspect}\e[0m"
    end
    result
  end

  def !=(expected)
    $spec_assertions = $spec_assertions + 1
    result = @target != expected
    if result
    else
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected not to equal #{expected.inspect} but got #{@target.inspect}\e[0m"
    end
    result
  end

  def nil?
    $spec_assertions = $spec_assertions + 1
    result = @target.nil?
    if result
    else
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected to be nil\e[0m"
    end
    result
  end

  def method_missing(method, *args)
    $spec_assertions = $spec_assertions + 1
    result = @target.__send__(method, *args)

    if result
    else
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected to be truthy\e[0m"
    end
    result
  end
end

class ShouldNotProxy
  def initialize(target)
    @target = target
  end

  def ==(expected)
    $spec_assertions = $spec_assertions + 1
    result = @target == expected
    if result
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected #{@target.inspect} != #{expected.inspect}\e[0m"
    end
    result
  end

  def method_missing(method, *args)
    $spec_assertions = $spec_assertions + 1
    result = @target.__send__(method, *args)
    if result
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected to be falsy, got #{@result.inspect}\e[0m"
    end
    result
  end
end

# Add should/should_not to Object
class Object
  def should(*args)
    if args.length == 0
      return ShouldProxy.new(self)
    end

    $spec_assertions = $spec_assertions + 1
    matcher = args[0]
    match_result = matcher.match?(self)
    if match_result == false
      $current_test_has_failure = true
      matcher_name = matcher.class.name
      failure_msg = matcher.failure_message(self) if matcher.respond_to?(:failure_message)
      if failure_msg
        puts "\e[31m    FAILED: #{failure_msg}\e[0m"
      else
        puts "\e[31m    FAILED: #{matcher_name}\e[0m"
      end
      return false
    end
    return true
  end

  def should_not(*args)
    if args.length == 0
      return ShouldNotProxy.new(self)
    end

    $spec_assertions = $spec_assertions + 1
    matcher = args[0]
    if matcher.match?(self)
      $current_test_has_failure = true
      matcher_name = matcher.class.name
      puts "\e[31m    FAILED: should_not #{matcher_name}\e[0m"
      return false
    end
    true
  end
end

# Matcher methods
# Note: == is handled by ShouldProxy#== for the .should == syntax
# We don't need a top-level == matcher method

def equal(expected)
  EqualObjectMatcher.new(expected)
end

def eql(expected)
  EqualMatcher.new(expected)
end

def be_true
  BeTrueMatcher.new
end

def be_false
  BeFalseMatcher.new
end

def be_nil
  BeNilMatcher.new
end

def raise_error(exception = nil, pattern = nil)
  RaiseErrorMatcher.new(exception, pattern)
end

def be_an_instance_of(klass)
  InstanceOfMatcher.new(klass)
end

def be_kind_of(klass)
  InstanceOfMatcher.new(klass)
end

def be_close(expected, tolerance)
  BeCloseMatcher.new(expected, tolerance)
end

class BeCloseMatcher < Matcher
  def initialize(expected, tolerance)
    @expected = expected
    @tolerance = tolerance
  end

  def match?(actual)
    diff = actual - @expected
    if diff < 0
      diff = -diff
    end
    diff <= @tolerance
  end

  def failure_message(actual)
    "Expected #{actual} to be within #{@tolerance} of #{@expected}"
  end
end

# STUB: complain matcher - used to test warning output
# Since we don't capture STDERR warnings, just skip these tests
def complain(pattern = nil)
  ComplainMatcher.new(pattern)
end

class ComplainMatcher
  def initialize(pattern)
    @pattern = pattern
  end

  def match?(actual)
    # Call the lambda/proc to execute the code
    if actual.is_a?(Proc)
      actual.call
    end

    # Since we don't capture warnings, mark as skipped
    $spec_skipped = $spec_skipped + 1
    $spec_assertions = $spec_assertions - 1

    # Always return true to skip the warning check
    true
  end

  def failure_message(actual)
    "Warning capture not implemented"
  end
end

# Guards - stub out for now
def ruby_version_is(*args)
  if block_given?
    yield
  end
end

def platform_is(*args)
  if block_given?
    # Handle hash arguments like platform_is c_long_size: 64
    if args.length == 1 && args[0].is_a?(Hash)
      hash = args[0]
      # Check c_long_size guard
      if hash[:c_long_size]
        expected = hash[:c_long_size]
        actual = c_long_size
        if expected == actual
          yield
        end
        # Don't yield - we handled the hash case
        return
      end
    end

    # For other platforms (like :linux, :windows, etc), just yield
    # since we don't have platform detection implemented yet
    yield
  end
end

def platform_is_not(*args)
  if block_given?
    # Handle hash arguments like platform_is_not c_long_size: 64
    if args.length == 1 && args[0].is_a?(Hash)
      hash = args[0]
      # Check c_long_size guard (inverted)
      if hash[:c_long_size]
        expected = hash[:c_long_size]
        actual = c_long_size
        if expected != actual
          yield
        end
        return
      end
    end
  end
end

def ruby_bug(*args)
  # Skip specs marked as ruby bugs
end

def conflicts_with(*args)
  # Skip conflicting specs
end

def not_supported_on(*args)
  # Skip specs not supported on certain platforms
  if block_given?
    yield
  end
end

# Context is an alias for describe
def context(description, &block)
  describe(description, &block)
end

# Global variable to pass method name to shared examples
# WORKAROUND: Avoids needing instance_eval since @method is replaced with
# $spec_shared_method during preprocessing (see run_rubyspec)
$spec_shared_method = nil

# Shared examples - retrieve and execute stored shared example blocks
def it_behaves_like(name, *args)
  block = $shared_examples[name]
  if block
    # Set global variable for shared examples to use
    # (preprocessing replaces @method with $spec_shared_method)
    $spec_shared_method = args[0] if args.length > 0
    block.call
  else
    msg = "behaves like '#{name}' (shared example not found)"
    it msg do
      $spec_skipped = $spec_skipped + 1
    end
  end
end

# Hooks
def before(type = :each, &block)
  if type == :each
    $before_each_blocks.push(block)
  elsif type == :all
    # Execute before :all blocks immediately
    block.call if block
  end
end

def after(type = :each, &block)
  if type == :each
    $after_each_blocks.push(block)
  elsif type == :all
    # Execute after :all blocks immediately (not ideal but simple)
    block.call if block
  end
end

# Helper methods from MSpec
# FIXME: These are fake values for 32-bit compatibility
# The real Ruby values would be 64-bit bignums, but:
# 1) The parser has issues with hex literals (especially with underscores)
# 2) The 32-bit implementation doesn't support actual bignums
# These values allow tests to run but don't actually test bignum behavior
def bignum_value(plus = 0)
  # Returns 2^64 + plus (a value that requires multiple limbs)
  # Now that we have large integer literal support, we can use the real value
  18446744073709551616 + plus
end

def infinity_value
  # Return Float::INFINITY
  Float::INFINITY
end

def nan_value
  # Return Float::NAN
  # WORKAROUND: Float not fully implemented, return nil as placeholder
  # Tests using NAN will fail but won't crash with method_missing
  nil
end

def fixnum_max
  # This compiler uses 30-bit signed integers with 1-bit tagging
  # Range: -2^29 to 2^29-1
  536870911  # 0x1FFFFFFF = 2^29 - 1
end

def fixnum_min
  # This compiler uses 30-bit signed integers with 1-bit tagging
  # Range: -2^29 to 2^29-1
  -536870912  # -0x20000000 = -2^29
end

def c_long_size
  # Size of C long in bytes (32-bit = 4 bytes)
  4
end

def min_long
  # Minimum value for a C long (32-bit signed)
  # -2^31 = -2147483648
  -2147483648
end

def max_long
  # Maximum value for a C long (32-bit signed)
  # 2^31 - 1 = 2147483647
  2147483647
end

# Helper to create mock object that responds to to_int
# FIXME: This is a minimal stub class, not a proper mock
# DISABLED: Causes crash during class definition
# class MockInt
#   def initialize(value)
#     @value = value
#   end
#
#   def to_int
#     @value
#   end
#
#   def __get_raw
#     %s(sar (callm @value __get_raw))
#   end
# end

def mock_int(value)
  # MockInt.new(value)
  # Return a simple fixnum for now
  value
end

# STUB: ruby_exe - used by rubyspecs to test subprocess execution
# Full implementation would compile and execute Ruby code as a subprocess
# For now, just skip tests that use this functionality
def ruby_exe(code, options = nil)
  # Mark this as skipped since we can't execute subprocesses yet
  # NOTE: This is a stub to prevent SEGFAULTs. Full implementation will
  # compile code to a temporary binary and execute it, capturing output.
  # See WORK_STATUS.md Priority 6 for future implementation.
  $spec_skipped = $spec_skipped + 1
  ""  # Return empty string to avoid nil errors
end

# Call this at end of spec file manually
def print_spec_results
  puts
  total = $spec_passed + $spec_failed + $spec_skipped
  puts "\e[32m#{$spec_passed} passed\e[0m, \e[31m#{$spec_failed} failed\e[0m, \e[33m#{$spec_skipped} skipped\e[0m (#{total} total)"
  # Exit with error code if there are failures OR skipped tests
  exit(1) if $spec_failed > 0 || $spec_skipped > 0
end
