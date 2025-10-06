# RubySpec Integration Proposal

## Executive Summary

This document outlines a stepwise approach to integrate the [Ruby Spec Suite](https://github.com/ruby/spec) (rubyspec) into the compiler test infrastructure. The rubyspec suite provides comprehensive, implementation-agnostic tests for Ruby language features and standard library functionality.

**Core Approach**: Create a minimal `rubyspec_helper.rb` that implements the MSpec API, allowing rubyspec files to be **compiled directly** as standalone test programs. This is a separate test suite from the existing RSpec infrastructure.

**Why This Works**:
- Rubyspec files are just Ruby code using `describe`, `it`, and matcher methods
- We provide a compatible implementation of these methods
- Compile each spec file as a normal Ruby program
- Run the compiled binary - it executes tests and reports results
- Simple, direct, and leverages existing compiler infrastructure

## Background

### Current Test Infrastructure

The compiler currently has three test layers:

1. **RSpec Tests** (`spec/*.rb`): Unit and compilation tests
   - Uses `CompilationHelper` to compile and run code snippets
   - Tests specific compiler components and language features
   - Run via `make rspec`

2. **Cucumber Features** (`features/*.feature`): Integration tests
   - Behavioral tests for end-to-end scenarios
   - Run via `make features`

3. **Self-Test Suite** (`test/selftest.rb`): Bootstrap validation
   - Minimal self-hosted test framework
   - Validates compiler can compile itself
   - Run via `make selftest`

### RubySpec Characteristics

The Ruby Spec Suite:
- Contains ~10,000+ specs testing Ruby language and standard library
- Uses **MSpec**, a simplified RSpec-like framework designed for testing Ruby implementations
- Organized into directories:
  - `language/`: Ruby syntax and semantics (if, while, class, def, etc.)
  - `core/`: Core classes (Array, Hash, String, Integer, etc.)
  - `library/`: Standard library (Set, Date, OpenStruct, etc.)
  - `optional/capi/`: C API specs (not relevant for this compiler)
  - `command_line/`: Ruby command-line flags (not relevant)

- Uses MSpec features:
  - Guards: `ruby_version_is`, `platform_is`, etc.
  - Shared examples: Reusable test behaviors
  - Fixtures: Test data and helper classes
  - Tags: Mark implementation-specific failures

## Challenges

### Compiler Limitations

The compiler has significant missing functionality that will prevent many specs from running:

1. **Missing Language Features**:
   - Exceptions (begin/rescue/ensure) - limited support
   - Regular expressions
   - Float/BigDecimal
   - Symbols (partial support)
   - String interpolation (partial support)
   - Multiple assignment edge cases
   - Many metaprogramming features

2. **Missing Standard Library**:
   - Most stdlib classes not implemented
   - Limited String methods
   - Limited Array/Hash methods
   - No File/IO operations
   - No networking, threads, etc.

3. **Compilation Model Differences**:
   - Static ahead-of-time compilation vs. interpretation
   - No `eval` or runtime code generation
   - `require` is compile-time, not runtime
   - No C extension support

### MSpec Dependencies

- MSpec itself requires Ruby 2.6+ with many features this compiler lacks
- Cannot run MSpec directly with the compiled Ruby
- Need to extract and adapt the spec format

## Proposed Solution: Direct Compilation with Spec Helper

### Architecture Overview

```
rubyspec/                    # Git clone of ruby/spec
├── language/
├── core/
└── library/

rubyspec_helper.rb           # MSpec-compatible API implementation
rubyspec_support/            # Support utilities
├── scratchpad.rb            # Test state tracking
├── fixtures.rb              # Fixture loading helpers
└── guards.rb                # Version/platform guards

rubyspec-tags/               # Compiler-specific exclusions
└── excluded_files.txt       # Specs we can't compile yet

out/rubyspec/                # Compiled spec binaries
└── ...
```

### Core Component: The Spec Helper

Create `rubyspec_helper.rb` that implements the MSpec API:

```ruby
# rubyspec_helper.rb - Minimal MSpec-compatible implementation

$spec_passed = 0
$spec_failed = 0
$spec_context = []

def describe(description, &block)
  $spec_context.push(description)
  block.call
  $spec_context.pop
end

def it(description, &block)
  begin
    block.call
    $spec_passed = $spec_passed + 1
    puts "  ✓ #{description}"
  rescue => e
    $spec_failed = $spec_failed + 1
    puts "  ✗ #{description}"
    puts "    #{e.message}"
  end
end

class Object
  def should(matcher)
    unless matcher.match?(self)
      raise "Expected #{matcher.expected}, got #{self.inspect}"
    end
  end

  def should_not(matcher)
    if matcher.match?(self)
      raise "Expected not #{matcher.expected}, got #{self.inspect}"
    end
  end
end

class EqualMatcher
  def initialize(expected)
    @expected = expected
  end

  def match?(actual)
    actual == @expected
  end

  def expected
    @expected.inspect
  end
end

def ==(expected)
  EqualMatcher.new(expected)
end

# Guards - stub out initially
def ruby_version_is(*args, &block)
  block.call  # Always run for now
end

def platform_is(*args, &block)
  block.call  # Always run for now
end

# At end of spec file
at_exit do
  puts
  puts "#{$spec_passed} passed, #{$spec_failed} failed"
end
```

**Key Insight**: Rubyspec files are just Ruby code. We provide the methods they expect, compile normally, and the binary runs the tests.

### Compilation Workflow

```bash
# 1. Clone rubyspec
git clone https://github.com/ruby/spec.git rubyspec

# 2. Compile a spec file directly
./compile rubyspec/core/integer/times_spec.rb -I. -I rubyspec

# 3. Run the compiled binary
./out/times_spec

# Output:
#   ✓ Integer#times yields the current index
#   ✓ Integer#times returns self
#   ✓ Integer#times skips execution for zero
#
#   3 passed, 0 failed
```

### Handling MSpec Features

| MSpec Feature | Initial Strategy | Future Enhancement |
|---------------|------------------|-------------------|
| `describe`/`it` | Implement directly | Add nested context tracking |
| `.should ==` | Implement matchers | Add more matcher types |
| `before(:each)` | Implement as instance variables | Full hook support |
| `ruby_version_is` | Stub (always run) | Implement version checking |
| `it_behaves_like` | Skip (tag file as excluded) | Inline shared examples |
| `ScratchPad` | Implement as global | Keep as-is |
| Fixtures | Adapt paths to work | Auto-copy fixtures |
| `eval` | Tag file as excluded | No support (AOT compilation) |

## Implementation Phases

### Phase 1: Minimal Spec Helper (Day 1-2)

**Goal**: Get 1-2 simple spec files compiling and running

**Tasks**:
1. Clone rubyspec: `git clone https://github.com/ruby/spec.git rubyspec`
2. Create minimal `rubyspec_helper.rb` with:
   - `describe`, `it` methods
   - Basic `.should ==` matcher
   - Pass/fail counting and reporting
3. Pick the simplest spec file (e.g., `core/true_class/`)
4. Manually adapt it if needed (replace requires, inline fixtures)
5. Compile and run: `./compile adapted_spec.rb -I.`

**Success Criteria**:
- 1-2 spec files compile successfully
- Can see which individual specs pass/fail
- Validated that direct compilation approach works

**Example**:
```bash
./compile rubyspec/core/true_class/to_s_spec.rb -I. -I rubyspec
./out/to_s_spec
# ✓ TrueClass#to_s returns "true"
# 1 passed, 0 failed
```

### Phase 2: Core Spec Helper Features (Week 1)

**Goal**: Support enough MSpec features to run 10-20 spec files

**Tasks**:
1. Enhance spec helper:
   - More matchers: `.should_not`, `.should <`, `.should >`, etc.
   - `before(:each)` / `after(:each)` hooks
   - `ScratchPad` utility class
   - Platform/version guards (stubbed out)
2. Test with simple core specs:
   - `core/true_class/*.rb`
   - `core/false_class/*.rb`
   - `core/nil_class/*.rb`
   - Simple `core/integer/*.rb` files
3. Create `excluded_files.txt` for specs we can't compile
4. Simple runner script to compile multiple specs

**Success Criteria**:
- 10-20 spec files compile and run
- Spec helper handles common MSpec patterns
- Basic exclusion mechanism working

**Makefile Integration**:
```makefile
rubyspec-setup:
	git clone https://github.com/ruby/spec.git rubyspec

rubyspec-simple:
	./compile rubyspec/core/true_class/to_s_spec.rb -I. -I rubyspec && ./out/to_s_spec

.PHONY: rubyspec-setup rubyspec-simple
```

### Phase 3: Batch Runner (Week 2)

**Goal**: Automate running multiple spec files

**Tasks**:
1. Create `run_rubyspecs.rb`:
   - Read list of spec files to run
   - Compile each spec file
   - Run compiled binary
   - Collect results
   - Generate summary report
2. Add more matchers and features as needed:
   - `.should raise_error`
   - `.should be_nil`, `.should be_true`, etc.
   - Better error messages
3. Test with 30-50 simple specs

**Success Criteria**:
- Can run batch of specs with one command
- Summary report showing pass/fail counts per file
- Total pass/fail/excluded counts

**Example Output**:
```
Running RubySpec Suite...

core/true_class/to_s_spec.rb:        1 passed, 0 failed
core/false_class/to_s_spec.rb:       1 passed, 0 failed
core/nil_class/to_s_spec.rb:         1 passed, 0 failed
core/integer/times_spec.rb:          8 passed, 2 failed
...

Total: 45 passed, 5 failed, 12 files excluded
```

### Phase 4: Expand Core Coverage (Week 3-4)

**Goal**: Run specs for all implemented core methods

**Tasks**:
1. Audit implemented methods in:
   - Integer
   - Array
   - Hash
   - String
2. For each implemented method, try to run its spec
3. Enhance spec helper as needed:
   - Fixture loading
   - Shared examples (simple cases or inline)
   - More sophisticated matchers
4. Create method coverage matrix

**Success Criteria**:
- 50+ spec files running
- Coverage report for core classes
- Identified missing methods vs. buggy methods

### Phase 5: Language Specs (Week 5-6)

**Goal**: Validate language features

**Tasks**:
1. Start with simplest language specs:
   - Control flow: `if`, `while`, `until`, `case`
   - Method/class definitions: `def`, `class`
   - Variables: local, instance, class
2. Handle challenges:
   - Specs using `eval` → exclude or rewrite
   - Complex metaprogramming → exclude
   - Missing features → exclude
3. Fix bugs revealed by language specs

**Success Criteria**:
- 20+ language spec files running
- Core language features validated
- Bug fixes for language feature edge cases

### Phase 6: Integration and Automation (Ongoing)

**Goals**:
- Make rubyspec part of regular test suite
- Track progress over time
- Use specs to guide development

**Tasks**:
1. Add to `make tests` target
2. Create progress tracking:
   - Historical pass rates
   - Coverage by category
   - Recently fixed specs
3. Use spec failures to prioritize:
   - Bug fixes
   - Missing features
   - Core method implementations
4. Periodically sync with upstream rubyspec

**Success Criteria**:
- Rubyspec runs automatically with other tests
- Progress metrics tracked
- Spec-driven development workflow established

## Technical Details

### Test Harness Design

Each spec will be wrapped in a minimal test harness:

```ruby
# Generated test program for a single spec
class SpecResult
  def self.record_pass
    puts "SPEC:PASS"
  end

  def self.record_fail(message)
    puts "SPEC:FAIL:#{message}"
  end
end

begin
  # Original spec code goes here
  # Example:
  result = (if true then 1 else 2 end)
  if result == 1
    SpecResult.record_pass
  else
    SpecResult.record_fail("Expected 1, got #{result}")
  end
rescue => e
  SpecResult.record_fail("Exception: #{e.message}")
end
```

The runner parses `SPEC:PASS` or `SPEC:FAIL:...` from the output.

### Handling Shared Examples

MSpec shared examples must be inlined:

```ruby
# Original MSpec:
it_behaves_like :array_push, :push

# Converted for compiler:
# Inline the shared example directly into the spec
# Or skip if shared example is too complex
```

### Handling Fixtures

Fixture files from `rubyspec/fixtures/` will need adaptation:

1. **Simple fixtures**: Copy and inline into test programs
2. **Complex fixtures**: Create adapted versions in `rubyspec-fixtures/`
3. **Unsupported fixtures**: Tag specs as excluded

### Compilation Strategy

Two possible approaches:

**Approach A: One Binary Per Spec File**
- Compile entire spec file as one program
- Run all specs in sequence
- Faster compilation, less granular reporting

**Approach B: One Binary Per `it` Block**
- Compile each `it` block separately
- Maximum isolation, granular reporting
- Slower but more robust

**Recommendation**: Start with Approach A, switch to Approach B if needed for debugging.

### Tagging Format

Use MSpec-compatible tag format:

```
# rubyspec-tags/core/array/push_fails.txt
fails:Array#push raises TypeError when object is frozen
fails:Array#push handles recursive arrays

# rubyspec-tags/core/string/encoding_excluded.txt
excluded:String#encode converts encoding
excluded:String#encoding returns encoding object
```

### Progress Tracking

Generate reports showing:

```
RubySpec Progress Report
========================

Language Specs:
  Total specs:     542
  Passing:         187 (34.5%)
  Failing:          45 (8.3%)
  Excluded:        310 (57.2%)

Core Specs:
  Total specs:    8234
  Passing:         421 (5.1%)
  Failing:          89 (1.1%)
  Excluded:       7724 (93.8%)

Top Failing Categories:
  1. Exceptions (45 specs)
  2. Regular expressions (234 specs)
  3. Float operations (156 specs)
  ...

Recently Fixed:
  - Integer#times with block
  - Array#each return value
  - Hash#[] with missing key
```

## Maintenance and Iteration

### Updating RubySpec

Periodically sync with upstream:

```bash
cd rubyspec
git pull origin master
cd ..
ruby rubyspec-runner/runner.rb --update-tags
```

### Adding New Specs

When implementing new compiler features:

1. Review relevant rubyspec files
2. Remove exclusion tags
3. Run specs
4. Fix failures
5. Update progress reports

### Continuous Integration

Add to CI pipeline:

```yaml
- name: Run RubySpec Suite
  run: make rubyspec
  continue-on-error: true  # Don't fail CI on spec failures initially

- name: Upload RubySpec Report
  uses: actions/upload-artifact@v2
  with:
    name: rubyspec-report
    path: rubyspec-runner/report.html
```

## Success Metrics

### Short-term (3 months)
- ✅ Custom runner implemented and working
- ✅ 100+ language specs passing
- ✅ 50+ core specs passing
- ✅ Automated tagging and filtering
- ✅ Progress tracking and reporting

### Medium-term (6 months)
- ✅ 300+ total specs passing
- ✅ All basic language features covered
- ✅ Integer, Array, Hash core coverage >50%
- ✅ Integration into regular test suite
- ✅ Identified and fixed 20+ compiler bugs

### Long-term (12+ months)
- ✅ 1000+ specs passing
- ✅ Comprehensive language feature coverage
- ✅ Core class coverage >60%
- ✅ Use spec failures to drive feature development
- ✅ Competitive with other alternative Ruby implementations

## Risks and Mitigations

### Risk: Overwhelming number of failing specs
**Mitigation**: Aggressive tagging/exclusion of unsupported features. Focus on growth in passing specs, not total coverage.

### Risk: Compilation time too slow
**Mitigation**: Implement parallel compilation, caching, and incremental builds. Start with subset of specs.

### Risk: MSpec features too complex to adapt
**Mitigation**: Start with simplest specs. Manually adapt complex patterns. Some specs may never be portable.

### Risk: Maintenance burden of tags
**Mitigation**: Automate tag generation. Regular audits to promote excluded→passing specs as features are added.

### Risk: Divergence from upstream rubyspec
**Mitigation**: Regular syncs. Document adaptation rationale. Contribute fixes back to rubyspec if appropriate.

## Alternatives Considered

### Alternative 1: Port MSpec to run on compiled Ruby
**Rejected**: MSpec requires too many Ruby features the compiler lacks. Would need to implement large parts of stdlib first.

### Alternative 2: Convert all specs to RSpec format
**Rejected**: Would lose ability to sync with upstream. Too much manual conversion work.

### Alternative 3: Use rubyspec as documentation only
**Rejected**: Misses opportunity for automated testing and validation. Low value compared to effort.

### Alternative 4: Write new compiler-specific tests instead
**Rejected**: Duplicates massive existing work. Rubyspec is battle-tested across multiple implementations.

## Conclusion

Integrating rubyspec through a custom runner provides:
- **Validation**: Comprehensive testing against canonical Ruby behavior
- **Documentation**: Specs serve as executable specification
- **Progress tracking**: Quantifiable metrics for compiler maturity
- **Bug discovery**: Uncover edge cases and subtle bugs
- **Roadmap**: Spec failures guide feature development priorities

The stepwise approach allows incremental adoption while managing the complexity of adapting a large test suite to an ahead-of-time compiled Ruby implementation.

**Recommended Next Step**: Begin Phase 1 implementation with a spike to validate the custom runner approach on 5-10 simple specs.
