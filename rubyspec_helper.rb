# rubyspec_helper.rb
# Minimal MSpec-compatible implementation for compiling rubyspec tests

$spec_passed = 0
$spec_failed = 0
$spec_skipped = 0
$spec_descriptions = []

def describe(description, &block)
  $spec_descriptions.push(description)
  puts description
  block.call
  $spec_descriptions.pop
end

def it(description, &block)
  failures_before = $spec_failed
  skipped_before = $spec_skipped
  block.call

  if $spec_skipped > skipped_before
    puts "\e[33m  - #{description}\e[0m"
  elsif $spec_failed == failures_before
    $spec_passed = $spec_passed + 1
    puts "\e[32m  ✓ #{description}\e[0m"
  else
    puts "\e[31m  ✗ #{description}\e[0m"
  end
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

# Proxy for chained matchers like obj.should.frozen?
class ShouldProxy
  def initialize(target)
    @target = target
  end

  def method_missing(method, *args)
    result = @target.__send__(method, *args)
    if result == false
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED: Expected to be truthy\e[0m"
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

    matcher = args[0]
    match_result = matcher.match?(self)
    if match_result == false
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED\e[0m"
      return false
    end
    return true
  end

  def should_not(matcher)
    if matcher.match?(self)
      $spec_failed = $spec_failed + 1
      puts "\e[33m    FAILED\e[0m"
      return false
    end
    true
  end
end

# Matcher methods
def ==(expected)
  EqualMatcher.new(expected)
end

def equal(expected)
  EqualObjectMatcher.new(expected)
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

# Shared examples - for now, just skip them
def it_behaves_like(name, *args)
  msg = "behaves like SHARED EXAMPLE (not supported)"
  it msg do
    $spec_skipped = $spec_skipped + 1
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
def bignum_value(plus = 0)
  0x8000_0000_0000_0000 + plus
end

def fixnum_max
  0x7FFF_FFFF_FFFF_FFFF
end

def fixnum_min
  -0x8000_0000_0000_0000
end

# Call this at end of spec file manually
def print_spec_results
  puts
  total = $spec_passed + $spec_failed + $spec_skipped
  puts "\e[32m#{$spec_passed} passed\e[0m, \e[31m#{$spec_failed} failed\e[0m, \e[33m#{$spec_skipped} skipped\e[0m (#{total} total)"
end
