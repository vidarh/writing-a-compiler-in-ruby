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
    __describe_call(block)
    $spec_descriptions.pop
  else
    $spec_descriptions.push(description)
    puts description
    __describe_call(block)
    $spec_descriptions.pop
  end
end

# Run a describe body, containing failures. A raise at REGISTRATION time (describe-level code
# touching an unimplemented class -- e.g. the whole core/time family died on `uninitialized
# constant Time` in describe bodies) used to abort the file before any summary printed,
# classifying every test in it as CRASH. mspec protects each context; do the same: count one
# failure for the broken context and let the rest of the file register and run.
def __describe_call(block)
  begin
    block.call
  rescue => e
    $spec_failed = $spec_failed + 1
    puts "    \e[31mFAILED: Unhandled exception in describe body: #{e.to_s}\e[0m"
  end
end

# mspec: quarantine! marks an example as quarantined (known-broken / environment-dependent). The block
# is NOT run; it counts as skipped. Without this, specs that call quarantine! crash with
# "undefined method 'quarantine!'" while loading, taking out the whole file.
def quarantine!(*args, &block)
  $spec_skipped = $spec_skipped + 1
end

# mspec: `evaluate <<-code do ... end` runs a code STRING at runtime (defining methods/classes), then runs
# the block of assertions against them. This AOT compiler cannot eval code strings, and the block's
# assertions reference methods defined only in that string -- so skip the example rather than crash. Without
# this, the undefined `evaluate` call hits a null vtable slot and SIGSEGVs while the file loads.
def evaluate(code = nil, &block)
  $spec_skipped = $spec_skipped + 1
end

def it(description, &block)
  # mspec: `it "desc"` with NO block is a PENDING example (counts as skipped, not run). Without this guard
  # the harness fell through to `block.call` on a nil block -> "undefined method 'call' for nil", crashing
  # the whole file. Many specs use a lone `it "needs to be reviewed for spec completeness"` placeholder.
  if block.nil?
    $spec_skipped = $spec_skipped + 1
    return
  end

  skipped_before = $spec_skipped
  assertions_before = $spec_assertions

  # Track whether this specific test had any assertion failures
  $current_test_has_failure = false

  # Run the before :each blocks INSIDE the rescue: a raise in a before block (e.g. fixtures
  # touching an unimplemented class) must fail THIS example and skip its body -- as mspec does --
  # not abort the whole file. An abort prints no summary, which classifies the entire spec file
  # as CRASH instead of recording the per-test failures.
  begin
    i = 0
    while i < $before_each_blocks.length
      $before_each_blocks[i].call
      i = i + 1
    end
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

  # FIXME: Stubs - should record expected call counts (parity with MockExpectationStub;
  # without these, `mock(x).should_receive(:y).once` falls into method_missing and
  # breaks the expectation chain).
  def once
    self
  end

  def twice
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

  # FIXME: Stub -- should make the mocked method yield the given args to a block. For now just chain so
  # specs using `.and_yield` don't crash with "undefined method 'and_yield'".
  def and_yield(*args)
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

  # Honour an explicit should_receive(:to_i) expectation (routed through method_missing so array/raise
  # returns work), otherwise fall back to 0. Previously this always returned 0, shadowing any stubbed
  # value -- a mock set up with should_receive(:to_i).and_return(:x) still saw 0.
  def to_i
    return method_missing(:to_i) if @expectations[:to_i]
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

# A mock that reports itself as a Numeric. Real mspec's mock_numeric builds a mock whose
# is_a?(Numeric)/kind_of?(Numeric) answer true, so that library code branching on `kind_of?(Numeric)`
# (Complex#==, Complex#coerce, numeric coercion, ...) takes the numeric path. A plain Mock returns false
# for is_a?(Numeric) (it is not a Numeric subclass), which made those specs take the wrong branch. Only
# Numeric is special-cased; every other class delegates to the normal Object#is_a?/kind_of?.
class NumericMock < Mock
  def is_a?(klass)
    return true if klass == Numeric
    super
  end

  def kind_of?(klass)
    return true if klass == Numeric
    super
  end
end

def mock_numeric(name)
  NumericMock.new(name)
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

  def include(expected)
    $spec_assertions = $spec_assertions + 1
    # Check if target responds to include?
    if @target.respond_to?(:include?)
      result = @target.include?(expected)
      if result
        $current_test_has_failure = true
        puts "\e[31m    FAILED: Expected #{@target.inspect} not to include #{expected.inspect}\e[0m"
      end
    else
      $current_test_has_failure = true
      puts "\e[31m    FAILED: #{@target.class} does not respond to include?\e[0m"
    end
  end

  def method_missing(method, *args)
    $spec_assertions = $spec_assertions + 1
    result = @target.__send__(method, *args)
    if result
      $current_test_has_failure = true
      puts "\e[31m    FAILED: Expected to be falsy, got #{result.inspect}\e[0m"
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
    if matcher.respond_to?(:skip_assertion?) && matcher.skip_assertion?
      # Skip-flavoured matcher (e.g. complain): run the block for its side effects,
      # count a skip (the matcher does the bookkeeping), never fail either polarity.
      matcher.match?(self)
      return true
    end
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
    if matcher.respond_to?(:skip_assertion?) && matcher.skip_assertion?
      matcher.match?(self)
      return true
    end
    if matcher.match?(self)
      $current_test_has_failure = true
      matcher_name = matcher.class.name
      puts "\e[31m    FAILED: should_not #{matcher_name}\e[0m"
      return false
    end
    true
  end

  # Mock expectations on a REAL object (Mock overrides these with full behaviour). We can't
  # intercept real method dispatch, so these are best-effort: should_not_receive is not
  # enforced and should_receive does not stub the return value. They return a chainable
  # null-expectation so a spec's `.and_return`/`.with`/`.exactly` chain doesn't crash.
  def should_receive(method)
    MockExpectationStub.new
  end

  def should_not_receive(method)
    MockExpectationStub.new
  end

  def stub!(method)
    MockExpectationStub.new
  end
end

# Chainable no-op returned by Object#should_receive/should_not_receive on real objects.
class MockExpectationStub
  def and_return(*a); self; end
  def and_raise(*a); self; end
  def and_yield(*a); self; end
  def with(*a); self; end
  def any_number_of_times; self; end
  def exactly(*a); self; end
  def at_least(*a); self; end
  def at_most(*a); self; end
  def times; self; end
  def once; self; end
  def twice; self; end
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

def include(expected)
  IncludeMatcher.new(expected)
end

class BeCloseMatcher < Matcher
  def initialize(expected, tolerance)
    @expected = expected
    @tolerance = tolerance
  end

  def match?(actual)
    # Magnitude of the difference, via #abs -- matches mspec's BeCloseMatcher and works for a Complex
    # difference too (Complex#abs), unlike a `< 0` / negate that assumes a real, ordered value.
    (actual - @expected).abs <= @tolerance
  end

  def failure_message(actual)
    "Expected #{actual} to be within #{@tolerance} of #{@expected}"
  end
end

# Float predicate matchers (be_nan / be_positive_infinity / be_negative_infinity / be_positive_zero /
# be_negative_zero). These lean on the now-real Float predicates: #nan?, #infinite? (1 / -1 / nil), and
# signed-zero detection via 1.0/z (+Inf for +0.0, -Inf for -0.0). float/divide, float/abs and the shared
# arithmetic specs use them.
def be_nan
  BeNaNMatcher.new
end

def be_positive_infinity
  BeInfinityMatcher.new(1)
end

def be_negative_infinity
  BeInfinityMatcher.new(-1)
end

def be_positive_zero
  BeSignedZeroMatcher.new(1)
end

def be_negative_zero
  BeSignedZeroMatcher.new(-1)
end

class BeNaNMatcher < Matcher
  def initialize
  end

  def match?(actual)
    actual.is_a?(Float) && actual.nan?
  end

  def failure_message(actual)
    "Expected #{actual} to be NaN"
  end
end

class BeInfinityMatcher < Matcher
  def initialize(sign)
    @sign = sign
  end

  def match?(actual)
    actual.is_a?(Float) && actual.infinite? == @sign
  end

  def failure_message(actual)
    dir = @sign > 0 ? "positive" : "negative"
    "Expected #{actual} to be #{dir} infinity"
  end
end

class BeSignedZeroMatcher < Matcher
  def initialize(sign)
    @sign = sign
  end

  def match?(actual)
    return false unless actual.is_a?(Float)
    return false unless actual == 0.0
    inf = 1.0 / actual
    if @sign > 0
      inf == Float::INFINITY
    else
      inf == (0.0 - Float::INFINITY)
    end
  end

  def failure_message(actual)
    dir = @sign > 0 ? "positive" : "negative"
    "Expected #{actual} to be #{dir} zero"
  end
end

class IncludeMatcher < Matcher
  def match?(actual)
    if actual.respond_to?(:include?)
      actual.include?(@expected)
    else
      false
    end
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to include #{@expected.inspect}"
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

  # We don't capture warning output, so both `should complain` and `should_not complain`
  # are recorded as skips (see the skip_assertion? protocol in Object#should/#should_not).
  def skip_assertion?
    true
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

# Reflection matchers (mspec's have_method / have_instance_method / have_constant /
# be_ancestor_of family).

class HaveMethodMatcher < Matcher
  def initialize(method, include_super = true)
    @method = method
    @include_super = include_super
  end

  def match?(actual)
    if actual.respond_to?(:methods)
      actual.methods(@include_super).include?(@method)
    else
      false
    end
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have method #{@method.inspect}"
  end
end

def have_method(method, include_super = true)
  HaveMethodMatcher.new(method, include_super)
end

class HaveInstanceMethodMatcher < Matcher
  def initialize(method, include_super = true)
    @method = method
    @include_super = include_super
  end

  def match?(actual)
    if actual.respond_to?(:method_defined?)
      actual.method_defined?(@method, @include_super)
    else
      false
    end
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have instance method #{@method.inspect}"
  end
end

def have_instance_method(method, include_super = true)
  HaveInstanceMethodMatcher.new(method, include_super)
end

def have_public_instance_method(method, include_super = true)
  HaveInstanceMethodMatcher.new(method, include_super)
end

class HaveConstantMatcher < Matcher
  def initialize(name)
    @name = name
  end

  def match?(actual)
    if actual.respond_to?(:constants)
      actual.constants.include?(@name)
    elsif actual.respond_to?(:const_defined?)
      actual.const_defined?(@name)
    else
      false
    end
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to have constant #{@name.inspect}"
  end
end

def have_constant(name)
  HaveConstantMatcher.new(name)
end

class BeAncestorOfMatcher < Matcher
  def initialize(subclass)
    @subclass = subclass
  end

  def match?(actual)
    @subclass.ancestors.include?(actual)
  end

  def failure_message(actual)
    "Expected #{actual.inspect} to be an ancestor of #{@subclass.inspect}"
  end
end

def be_ancestor_of(subclass)
  BeAncestorOfMatcher.new(subclass)
end

# Data-table matcher: `[[receiver, arg..., expected], ...].should be_computed_by(:meth, extra...)`
# verifies receiver.meth(arg..., extra...) == expected for every row.
class BeComputedByMatcher < Matcher
  def initialize(method, *args)
    @method = method
    @args = args
  end

  def match?(sets)
    i = 0
    while i < sets.length
      line = sets[i]
      receiver = line[0]
      expected = line[line.length - 1]
      arguments = []
      j = 1
      while j < line.length - 1
        arguments << line[j]
        j = j + 1
      end
      k = 0
      while k < @args.length
        arguments << @args[k]
        k = k + 1
      end
      value = receiver.__send__(@method, *arguments)
      if !(value == expected)
        @failed_receiver = receiver
        @failed_expected = expected
        @failed_value = value
        return false
      end
      i = i + 1
    end
    true
  end

  def failure_message(actual)
    "Expected #{@failed_expected.inspect} to be computed by #{@failed_receiver.inspect}.#{@method} (got #{@failed_value.inspect})"
  end
end

def be_computed_by(method, *args)
  BeComputedByMatcher.new(method, *args)
end

# Timezone helper: set ENV["TZ"] around the block. Our Time implementation is a stub,
# so this mainly stops whole-file aborts on the missing helper.
def with_timezone(name, offset = nil, dst = nil)
  old = ENV["TZ"]
  ENV["TZ"] = name
  begin
    yield
  ensure
    ENV["TZ"] = old
  end
end

# mspec's new_io helper (mspec/helpers/io.rb, absent from this checkout): open a
# File for the given name/mode. IOSpecs.io_fixture and ~24 io specs call it.
# The mode string may carry an encoding suffix ("r:utf-8"); strip it -- our
# File open ignores encodings. A Hash mode isn't used by the specs that reach here.
def new_io(name, mode = "w")
  m = mode
  if m.is_a?(String)
    c = m.index(":")
    m = m[0, c] if !c.nil?
  else
    m = "w"
  end
  File.new(name, m)
end

# Warning-category flags: enough for the `Warning[:experimental] = false` save/restore
# dance in before/after hooks. MRI defaults :experimental to true.
module Warning
  def self.[](category)
    flags = $__warning_categories
    if flags
      v = flags[category]
      return v if !v.nil?
    end
    category == :experimental
  end

  def self.[]=(category, value)
    $__warning_categories = {} if $__warning_categories.nil?
    $__warning_categories[category] = value
    value
  end
end

# We never emit the warnings these guard against; just run the block.
def suppress_keyword_warning
  yield
end

def suppress_warning
  yield
end

# Guards - stub out for now
def ruby_version_is(*args)
  if block_given?
    yield
  end
end

# mspec guard blocks the harness lacked: without them, specs that call them crash at load with
# "undefined method", taking out the whole file. Best-effort: run the block when the guard matches this
# environment (x86 little-endian, ordinary user), skip otherwise. Crash -> the file's specs actually run.
def guard(*args)
  yield if block_given?
end

def guard_not(*args)
  yield if block_given?
end

def little_endian
  yield if block_given?
end

def big_endian
  # x86 target is little-endian: big-endian-only specs are skipped (block not run).
end

def as_user
  yield if block_given?
end

def as_superuser
  # not running as root: superuser-only specs are skipped (block not run).
end

# mspec helper: tmp(name) returns a path for a temporary file. The harness lacked it, so the ~110 file/io
# specs that build paths via tmp(...) at load time crashed with "undefined method 'tmp'", losing the whole
# file. Use a flat prefix under /tmp (which exists) so no temp subdir needs creating.
SPEC_TEMP_PREFIX = "/tmp/rubyspec_"
def tmp(name, uniquify = true)
  SPEC_TEMP_PREFIX + name.to_s
end

# Minimal writable IO wrapper over a raw fd, used by touch's block form so specs that write real content
# (e.g. touch(f){|io| io.write 'rubinius'}) produce a file with that content instead of an empty one.
class SpecFileWriter
  def initialize(fd)
    @fd = fd   # tagged Integer fd
  end

  def write(str)
    s = str.to_s
    len = s.bytesize
    %s(write (callm @fd __get_raw) (callm s __get_raw) (callm len __get_raw))
    len
  end

  def print(*args)
    args.each { |a| write(a.to_s) }
    nil
  end

  def <<(str)
    write(str.to_s)
    self
  end

  def puts(*args)
    if args.empty?
      write("\n")
    else
      args.each { |a| write(a.to_s + "\n") }
    end
    nil
  end
end

# mspec helper: touch(file) creates/truncates the file. The block form yields a writable IO (backed by
# SpecFileWriter) so content written in the block actually lands on disk. Flags: O_WRONLY|O_CREAT|O_TRUNC
# = 577, mode 0644 = 420.
def touch(file, mode = "w")
  fdt = nil
  %s(assign rpath (callm file __get_raw))
  %s(assign fd (open rpath 577 420))
  %s(if (ge fd 0) (assign fdt (__int fd)))
  return nil if fdt.nil?
  if block_given?
    yield SpecFileWriter.new(fdt)
  end
  %s(close (callm fdt __get_raw))
  nil
end

# mspec file helpers. mkdir_p makes a directory path (parents included), ignoring already-exists errors.
# rm_r / rm_rf remove files and (empty) directories best-effort -- they are cleanup, so failures are
# ignored rather than raised. These lived only in real mspec (FileUtils), so specs using them to set up
# or tear down temp files crashed at "undefined method 'mkdir_p'/'rm_r'".
def mkdir_p(*dirs)
  dirs.each do |dir|
    d = dir.to_s
    parts = d.split("/")
    path = d.start_with?("/") ? "" : "."
    parts.each do |part|
      next if part.empty?
      path = path + "/" + part
      %s(mkdir (callm path __get_raw) 511)
    end
  end
  nil
end

def rm_r(*paths)
  paths.each do |path|
    p = path.to_s
    # Try to remove as a file first, then as a directory. Best-effort: ignore failures.
    %s(assign rp (callm p __get_raw))
    %s(unlink rp)
    %s(rmdir rp)
  end
  nil
end

def rm_rf(*paths)
  rm_r(*paths)
end

# mspec helper: mock_to_path(path) returns an object whose #to_path returns the given path (used to test
# that File/IO methods call #to_path on their argument). Backed by the existing mock framework.
def mock_to_path(path)
  m = mock(path.to_s)
  m.should_receive(:to_path).and_return(path)
  m
end

# mspec helper: new_io(name, mode) opens a file-backed IO. In real mspec this is a top-level helper, so
# it is reachable both bare and as IOSpecs.new_io (a module is an object). File < IO here, so File.new
# gives an IO; the mode may carry an :encoding suffix ("w:utf-8") which File.__mode_to_flags ignores.
# Default mode is "w" (matching mspec's "w:utf-8"): a bare new_io(name) CREATES a fresh writable file.
def new_io(name, mode = "w")
  mode = "w" if !mode.is_a?(String)
  File.new(name, mode)
end

# mspec helper: new_fd(name, mode) opens a file and returns its raw fd (mspec uses IO.sysopen). Default
# "w" creates the file, matching new_io.
def new_fd(name, mode = "w")
  mode = "w" if !mode.is_a?(String)
  IO.sysopen(name, mode)
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

def skip(message = nil)
  # Mark the current test as skipped
  $spec_skipped = $spec_skipped + 1
  # Prevent the test from being counted as failed
  $current_test_has_failure = false
end

# suppress_warning helper used by some specs
# In MRI this temporarily suppresses warnings, but we don't have warnings
def suppress_warning
  yield
end

# Context is an alias for describe
def context(description, &block)
  describe(description, &block)
end

# let - defines a memoized helper method for specs
# Simple implementation: defines a method that caches its result
# Cache is stored in a global hash keyed by method name
$__let_cache = {}

def let(name, &blk)
  # Store the block for this name
  $__let_blocks ||= {}
  $__let_blocks[name] = blk

  # Define a method that evaluates the block lazily and memoizes result
  # Use Object.send(:define_method, ...) to define at top level
  Object.send(:define_method, name) do
    $__let_cache[name] ||= $__let_blocks[name].call
  end
end

# Clear let cache between tests
def clear_let_cache
  $__let_cache = {}
end

# Global variable to pass method name to shared examples
# WORKAROUND: Avoids needing instance_eval since @method is replaced with
# $spec_shared_method during preprocessing (see run_rubyspec)
$spec_shared_method = nil

# Shared examples - retrieve and execute stored shared example blocks
def it_behaves_like(name, *args)
  block = $shared_examples[name]
  if block
    # Set global variables for shared examples to use
    # (preprocessing replaces @method with $spec_shared_method and other @ivars with $spec_<name>).
    # mspec's it_behaves_like(desc, method, object) binds @method and @object; the second extra arg
    # becomes @object (used by e.g. shared/string/times.rb as `@object.call(...)`). Without setting
    # $spec_object, @object stayed nil and `@object.call` SEGFAULTED.
    $spec_shared_method = args[0] if args.length > 0
    $spec_object = args[1] if args.length > 1
    block.call
  else
    msg = "behaves like '#{name}' (shared example not found)"
    it msg do
      $spec_skipped = $spec_skipped + 1
    end
  end
end

# Deprecated mspec alias for it_behaves_like.
def it_should_behave_like(name, *args)
  it_behaves_like(name, *args)
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
def bignum_value(plus = 0)
  # Returns 2^64 + plus (a value that requires multiple limbs)
  18446744073709551616 + plus
end

def infinity_value
  # Return Float::INFINITY
  Float::INFINITY
end

def nan_value
  # A real IEEE NaN. Float is now fully implemented (literals assemble to real IEEE doubles and
  # 0.0/0.0 yields an actual NaN whose #nan? is true, #== is false against itself, and #-@ stays NaN),
  # so the old `0.0` placeholder is obsolete -- it made every NaN-specific assertion (float/nan,
  # float/finite, float/uminus, the math specs) silently wrong. `-nan_value` is still a valid Float, so
  # the `[..., nan_value].map { |n| [n, -n] }` helper constructions remain safe.
  0.0 / 0.0
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

# STUB: have_private_instance_method matcher
# We don't track private method visibility, so always fail
def have_private_instance_method(method_name, include_super = true)
  HavePrivateInstanceMethodMatcher.new(method_name)
end

class HavePrivateInstanceMethodMatcher
  def initialize(method_name)
    @method_name = method_name
  end

  def match?(actual)
    # We don't track private methods, always return false
    false
  end

  def failure_message(actual)
    "Expected #{actual} to have private instance method #{@method_name}"
  end
end

# STUB: have_public_instance_method matcher
def have_public_instance_method(method_name, include_super = true)
  HavePublicInstanceMethodMatcher.new(method_name)
end

class HavePublicInstanceMethodMatcher
  def initialize(method_name)
    @method_name = method_name
  end

  def match?(actual)
    # Check if the class responds to instance_methods and has this method
    if actual.respond_to?(:instance_methods)
      actual.instance_methods.include?(@method_name)
    else
      false
    end
  end

  def failure_message(actual)
    "Expected #{actual} to have public instance method #{@method_name}"
  end
end

# Call this at end of spec file manually
def print_spec_results
  puts
  total = $spec_passed + $spec_failed + $spec_skipped
  puts "\e[32m#{$spec_passed} passed\e[0m, \e[31m#{$spec_failed} failed\e[0m, \e[33m#{$spec_skipped} skipped\e[0m (#{total} total)"
  # Exit with error code if there are failures OR skipped tests
  exit(1) if $spec_failed > 0 || $spec_skipped > 0
end
