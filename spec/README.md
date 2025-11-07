# spec/ Directory

**Purpose**: Custom mspec-compatible test cases

## CRITICAL: Tests Must Use mspec Format

All tests in spec/ **MUST** be mspec-compatible because `make spec` runs `./run_rubyspec ./spec`.

**Required format**:
```ruby
require_relative '../rubyspec/spec_helper'

describe "Feature being tested" do
  it "specific behavior" do
    result = some_code
    result.should == expected_value
  end
end
```

Tests are **NOT** plain Ruby scripts - they must use the mspec framework (describe/it/.should).

## What Goes in spec/

1. **Reduced test cases** - Minimal mspec tests reproducing specific bugs
2. **Compiler-specific tests** - Tests using compiler classes directly (via mspec)
3. **Feature verification** - Tests for features not covered by rubyspec
4. **Custom tests** - Tests that deviate from rubyspec format but still use mspec

## Usage

Run all tests:
```bash
make spec              # Runs ./run_rubyspec ./spec, saves to docs/spec.txt
```

Run specific test:
```bash
./run_rubyspec spec/my_test_spec.rb
```

## Guidelines

- **MUST use mspec format** - Tests won't run otherwise
- Name files with `_spec.rb` suffix (e.g., `ternary_operator_spec.rb`)
- Keep tests minimal and focused on specific issues
- Reference KNOWN_ISSUES.md issue numbers in comments
- Delete/move to rubyspec/ once integrated into main test suite

## Example

See `spec/ternary_operator_spec.rb` for a proper mspec test example.

## Main Test Suites

- `make selftest` / `make selftest-c` - Self-hosting validation (MUST PASS)
- `make rubyspec-integer` - Integer compatibility tests
- `make rubyspec-language` - Language feature tests
- `make spec` - Custom tests (this directory)
