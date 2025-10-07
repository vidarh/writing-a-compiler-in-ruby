# rubyspec_helper.rb
# Minimal MSpec-compatible implementation for compiling rubyspec tests

$spec_passed = 0
$spec_failed = 0
$spec_skipped = 0
$spec_assertions = 0
$spec_descriptions = []
$shared_examples = {}
$spec_method = nil

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
  failures_before = $spec_failed
  skipped_before = $spec_skipped
  assertions_before = $spec_assertions

  block.call

  if $spec_skipped > skipped_before
    puts "\e[33m  - #{description}\e[0m"
  elsif $spec_failed == failures_before
    # Check if any assertions were actually executed
    if $spec_assertions == assertions_before
      $spec_failed = $spec_failed + 1
      puts "\e[31m  ✗ #{description} (NO ASSERTIONS)\e[0m"
    else
      $spec_passed = $spec_passed + 1
      puts "\e[32m  ✓ #{description}\e[0m"
    end
  else
    puts "\e[31m  ✗ #{description}\e[0m"
  end
end

class Mock
  def initialize(name)
    @name = name
  end

  # FIXME: Need to track
  def should_receive(method)
    self
  end

  # FIXME: Need to track/enforce
  def any_number_of_times
    self
  end

  # FIXME: Need to track/enforce
  def and_return(result)
    self
  end

  # FIXME: Need to track/enforce - should actually raise the error
  def and_raise(error)
    self
  end

  def to_s
    @name
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
  def match?(actual)
    false
  end
  
  def failure_message(actual)
    "Exceptions not implemented"
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
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected #{expected.inspect} but got #{@target.inspect}\e[0m"
    end
    result
  end

  def nil?
    $spec_assertions = $spec_assertions + 1
    result = @target.nil?
    if result
    else
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected to be nil\e[0m"
    end
    result
  end

  def method_missing(method, *args)
    $spec_assertions = $spec_assertions + 1
    result = @target.__send__(method, *args)

    if result
    else
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected to be truthy\e[0m"
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
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected #{@target.inspect} != #{expected.inspect}\e[0m"
    end
    result
  end

  def method_missing(method, *args)
    $spec_assertions = $spec_assertions + 1
    result = @target.__send__(method, *args)
    if result
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected to be falsy, got #{@result.inspect}\e[0m"
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
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED\e[0m"
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
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED\e[0m"
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

def raise_error(exception)
  RaiseErrorMatcher.new(exception)
end

def be_an_instance_of(klass)
  InstanceOfMatcher.new(klass)
end

def be_kind_of(klass)
  InstanceOfMatcher.new(klass)
end

# Guards - stub out for now
def ruby_version_is(*args)
  if block_given?
    yield
  end
end

def platform_is(*args)
  if block_given?
    yield
  end
end

def platform_is_not(*args)
  if block_given?
    yield
  end
end

def ruby_bug(*args)
  # Skip specs marked as ruby bugs
end

def conflicts_with(*args)
  # Skip conflicting specs
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
$before_each_blocks = []
$after_each_blocks = []

def before(type, &block)
  if type == :each
    $before_each_blocks.push(block)
  end
end

def after(type, &block)
  if type == :each
    $after_each_blocks.push(block)
  end
end

# Helper methods from MSpec
# FIXME: These are fake values for 32-bit compatibility
# The real Ruby values would be 64-bit bignums, but:
# 1) The parser has issues with hex literals (especially with underscores)
# 2) The 32-bit implementation doesn't support actual bignums
# These values allow tests to run but don't actually test bignum behavior
def bignum_value(plus = 0)
  # Real value should be: 0x8000_0000_0000_0000 + plus
  # Using a safe 32-bit value instead
  100000 + plus
end

def fixnum_max
  # Real value should be: 0x7FFF_FFFF_FFFF_FFFF
  # Using 32-bit fixnum max (accounting for 1-bit tagging)
  1073741823  # 0x3FFFFFFF
end

def fixnum_min
  # Real value should be: -0x8000_0000_0000_0000
  # Using 32-bit fixnum min (accounting for 1-bit tagging)
  -1073741824  # -0x40000000
end

def c_long_size
  # Size of C long in bytes (32-bit = 4 bytes)
  4
end

# Call this at end of spec file manually
def print_spec_results
  puts
  total = $spec_passed + $spec_failed + $spec_skipped
  puts "\e[32m#{$spec_passed} passed\e[0m, \e[31m#{$spec_failed} failed\e[0m, \e[33m#{$spec_skipped} skipped\e[0m (#{total} total)"
  exit(1) if $spec_failed > 0
end
