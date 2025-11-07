# spec/ Directory

**Purpose**: Reduced test cases and compiler unit tests

This directory is for:

1. **Reduced test cases** - Minimal reproductions when investigating bugs
2. **Compiler class tests** - Tests that use compiler internals directly
3. **Feature verification** - Quick tests for specific features
4. **Tests that deviate from RubySpec** - Custom test cases not suitable for rubyspec/

## Usage

Run all tests in this directory:
```bash
make spec
```

Output is saved to `docs/spec.txt`

## Guidelines

- Keep tests minimal and focused
- Name files descriptively (e.g., `ternary_bug_minimal.rb`)
- Delete test files once bug is fixed and covered by rubyspec
- Use for temporary investigation, not permanent test suite

## Main Test Suite

The primary test suite is rubyspec/:
- `make rubyspec-integer` - Integer specs
- `make rubyspec-language` - Language specs
- `make selftest` - Self-hosting test
- `make selftest-c` - Self-compilation test
