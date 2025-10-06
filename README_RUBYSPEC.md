# RubySpec Integration

## Overview

This directory contains infrastructure for running rubyspec tests against the compiled Ruby implementation.

## Quick Start

```bash
# Run a simple spec
./run_rubyspec rubyspec/simple_true_to_s_spec.rb
./run_rubyspec rubyspec/simple_integer_basic_spec.rb
```

## Components

1. **rubyspec_helper.rb** - Minimal MSpec-compatible API
   - `describe`, `it`, `context` methods
   - Matchers: `should ==`, `be_true`, `be_false`, `be_nil`
   - `it_behaves_like` (stubs out shared examples as SKIPPED)
   - Guards: `ruby_version_is`, `platform_is`, `ruby_bug`, `conflicts_with` (stubbed)
   - No exception support (uses failure counting instead)
   - No `require_relative` or `at_exit` (not supported by compiler)

2. **run_rubyspec** - Script to compile and run spec files
   - Supports single file or directory (recursive)
   - Wraps specs in a method to avoid top-level block issues
   - Replaces `require_relative` with `require`
   - Adds results printing
   - Redirects stdin to prevent loop issues

3. **rubyspec/** - Cloned ruby/spec repository plus custom simple specs

## Compiler Limitations

Features NOT supported:
- `require_relative` - use `require` instead  
- `at_exit` - call `print_spec_results` manually
- `unless` - use `if !` instead
- Exceptions/raise - failures tracked via global variables
- `**` (exponentiation operator)
- `method_missing` (causes segfault)
- Many metaprogramming features

## Status

**Working**: 4 specs passing
- TrueClass#to_s
- Integer arithmetic (+, -, *)

**Features**:
- ✅ Color-coded output (green ✓ for pass, red ✗ for fail, yellow - for skip)
- ✅ Summary shows passed, failed, AND skipped counts
- ✅ Failure detection working correctly
- ✅ Matchers: `==`, `be_true`, `be_false`, `be_nil`
- ✅ Shared examples handled via `it_behaves_like` (marked as skipped)

**Known Issues**:
- Cannot override `==` as matcher name (conflicts with operator) - use explicit `EqualMatcher.new()`
- Default parameters don't work in Object class methods - use `*args` instead

**Next Steps**:
- Add more matchers (should_not, be_kind_of, etc.)
- Import/adapt more simple specs from ruby/spec
- Document method coverage for core classes
