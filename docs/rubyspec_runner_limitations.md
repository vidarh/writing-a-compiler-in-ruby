# RubySpec Runner Code Transformations and Limitations

## Overview

The `run_rubyspec` script applies several `sed` transformations to work around compiler limitations. Some of these transformations **mangle valid Ruby code**, causing parse errors that are NOT bugs in the parser itself.

## Problem: it_behaves_like Parenthesization

### The Transformation

Line 360 in `run_rubyspec`:
```bash
sed 's/^\([[:space:]]*\)it_behaves_like \(.*\)$/\1it_behaves_like(\2)/'
```

**Purpose**: Add parentheses to `it_behaves_like` calls to work around compiler bug where calling functions without parentheses when the function has default parameters + block causes segfaults.

**How it works**: Captures everything after `it_behaves_like` and wraps it in `()`, adding the closing `)` at the **end of the line**.

### The Problem

When `it_behaves_like` takes a lambda with a multi-line block, the transformation breaks:

**Original (valid Ruby):**
```ruby
it_behaves_like :locale, -> file {
  print_at_exit = fixture(__FILE__, "print_magic_comment_result_at_exit.rb")
  ruby_exe(nil, args: "< #{fixture(__FILE__, file)}")
}
```

**After sed transformation (INVALID):**
```ruby
it_behaves_like(:locale, -> file {)  # ❌ Closing ) in wrong place!
  print_at_exit = fixture(__FILE__, "print_magic_comment_result_at_exit.rb")
  ruby_exe(nil, args: "< #{fixture(__FILE__, file)}")
}
```

**Parser error:**
```
Parse error: Expected: '}' for '{'-block
```

The closing `)` is inserted **before** the `{` starts the block, making the parser think the `)` closes the method call early, then the `{` is unexpected.

### Affected Specs

Known specs with this issue:
1. **magic_comment_spec.rb**
   - Line 51: `it_behaves_like(:magic_comments, :locale, -> file {)`
   - Error: "Expected: '}' for '{'-block"

2. **predefined_spec.rb**
   - Line 794: `it_behaves_like(:exception_set_backtrace, -> backtrace {)`
   - Error: "Expected: '}' for '{'-block"

### Why This Happens

The sed pattern `\(.*\)$` captures everything to the end of the line, including the opening `{`. So:
- Input: `it_behaves_like :locale, -> file {`
- Captured: `:locale, -> file {`
- Output: `it_behaves_like(:locale, -> file {)`
- The `{` is **inside** the parentheses, but the `)` is at the end of the line

For single-line blocks this works fine:
```ruby
it_behaves_like :foo, -> { x }
# Becomes: it_behaves_like(:foo, -> { x })  ✓ Works!
```

But for multi-line blocks it breaks.

## Similar Issues

### describe/it/other methods with blocks

Other transformations that could have the same problem:
- Line 110: `sed 's/^\([[:space:]]*\)describe \(.*\) do$/\1describe(\2) do/'`
- This one is safer because it only matches lines ending with ` do`, not `{`

## Proper Fix

### Fix the Compiler Bug (ONLY Acceptable Solution)

The transformation exists to work around a compiler segfault. If we fix that bug, we can remove the transformation entirely.

**Root cause**: Calling methods without parentheses when the method has default parameters + block argument causes segfaults.

**Example that segfaults:**
```ruby
def foo(a, b = 1, &block)
  block.call
end

foo :x, :y do  # Segfaults!
  puts "hi"
end

foo(:x, :y) do  # Works with parens
  puts "hi"
end
```

If we fix this compiler bug, we can remove lines 110, 360, and related transformations.

**Do NOT try to fix the sed transformation** - it's as much work as fixing the underlying bug, and adds complexity to the test infrastructure. The sed transformations are temporary workarounds that should be removed once the compiler bugs are fixed.

## Other Transformations

The run_rubyspec script applies many other transformations. Documenting them here for reference:

### 1. Instance Variable → Global Variable
```bash
sed 's/@\([a-zA-Z_][a-zA-Z0-9_]*\)/$spec_\1/g'
```
- **Why**: `instance_eval` not implemented, so specs can't use instance variables
- **Impact**: Changes `@foo` to `$spec_foo`
- **Issues**: None known

### 2. Strip Literals from platform_is/ruby_bug/etc
```bash
sed 's/ruby_bug[^d]*do/ruby_bug do/g'
sed 's/ruby_version_is[^d]*do/ruby_version_is do/g'
sed 's/platform_is[^d]*do/platform_is do/g'
```
- **Why**: Hash literals and range literals passed to methods with blocks cause crashes
- **Impact**: Removes version/platform constraints (all specs run unconditionally)
- **Issues**: May run specs for wrong Ruby versions/platforms

### 3. Replace Empty Array Literals
```bash
sed 's/\.and_return(\[\])/.and_return(nil)/g'
```
- **Why**: Empty array `[]` passed to `and_return` causes crashes in mock framework
- **Impact**: Changes mock return values from `[]` to `nil`
- **Issues**: May cause test failures if code expects array

### 4. Convert Keyword Arguments to Hash Syntax
```bash
sed "s/, *shared: *true *do/, {:shared => true} do/"
```
- **Why**: Keyword argument syntax not fully supported
- **Impact**: Changes `shared: true` to `{:shared => true}`
- **Issues**: None known

## Recommendations

1. **Short term**: Document which spec errors are caused by sed mangling (this file) ✓ Done
2. **Fix the underlying bugs**: The ONLY acceptable long-term solution is to fix the compiler bugs that necessitate these transformations:
   - Method calls without parens + default params + block → segfault (enables removing lines 110, 360)
   - Hash/range literals passed to methods with blocks → crash (enables removing lines 362-366)
   - Empty array literals in mocks → crash (enables removing line 367)
   - Instance_eval not implemented (enables removing line 361)
3. **Do NOT**: Try to "fix" the sed transformations - it's as much work as fixing the compiler and adds test infrastructure complexity

## How to Debug

If you see a parsing error in a rubyspec:

1. **Check the temp file**: `cat rubyspec_temp_<spec_name>.rb | grep -A 5 "<error line>"`
2. **Compare to original**: `cat rubyspec/language/<spec_name>.rb | grep -A 5 "<error line>"`
3. **Look for sed artifacts**: Misplaced `)`, missing `{`, etc.
4. **Check this document**: Is it a known transformation issue?

## Status

**Last updated**: Session 42 (2025-11-03)
**Known affected specs**: magic_comment_spec, predefined_spec
**Workaround**: Manual testing by directly compiling fixed versions (without sed transformations)
