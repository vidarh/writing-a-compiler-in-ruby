# Ruby Compiler TODO

This document tracks known bugs, missing features, and architectural issues. Items are prioritized: critical bugs first, missing language features second, architectural improvements third.

## Current Integer Spec Test Status (2025-10-07)

**Summary**: 68 spec files total
- **PASS**: 7 specs (10%)
- **FAIL**: 12 specs (18%) - compile and run but have assertion failures
- **SEGFAULT**: 20 specs (29%) - compile but crash at runtime
- **COMPILE_FAIL**: 29 specs (43%) - fail to compile

### Top Blockers for Compile Failures

#### 1. Missing `context` Support - BLOCKS ~29 SPECS
**Impact**: PRIMARY blocker for compile failures

**Issue**: Many specs use `context` blocks (RSpec/MSpec feature), which aren't implemented in spec helper.

**Example failing spec** (`to_f_spec.rb`):
```ruby
describe "Integer#to_f" do
  context "fixnum" do    # <- Not implemented!
    it "returns self converted to a Float" do
      0.to_f.should == 0.0
    end
  end
end
```

**Error**: Parser error at `tokens.rb:383` - `undefined method '[]' for nil:NilClass`

**Fix needed**: Implement `context` as alias for `describe` in spec helper

**Why floats didn't help**: Float literals NOW WORK, but specs using floats also use `context`, so they fail at parse time before float code runs.

#### 2. Missing Spec Helper Methods/Matchers
- `be_kind_of` matcher - affects gcdlcm_spec
- `Object#Integer` method - affects multiple specs
- Mock functionality incomplete
- `platform_is` not implemented

#### 3. Missing `require_relative` Support
**Impact**: Affects specs that load fixtures

**Issue**: Spec files use `require_relative 'fixtures/...'` which isn't implemented. Need to either:
- Implement `require_relative` in compiler
- Rewrite calls to `require`
- Inline/embed the fixture files

Causes "failure to resolve" class names in error messages.

## Recent Additions (2025-10-07)

### ✅ Completed Features

**Exclusive Range Operator (...)** - WORKING
- Added `...` operator to `operators.rb`
- Updated `Range` class with `exclude_end` parameter
- Added transform rewrite for `:exclusive_range`
- Result: `ceil_spec` and `floor_spec` now compile

**Hex/Binary Literal Parsing** - WORKING
- Enhanced `tokens.rb` to support `0x` (hex) and `0b` (binary) prefixes
- Supports underscores as separators: `0xFFFF_FFFF`, `0b1010_1010`
- Respects 29-bit limit to prevent overflow
- Result: No more "Method missing Object#xffff" errors

**Float Literal Support** - WORKING (but blocked by context issue)
- Created `Float` class with instance variables reserving 8-byte space
- Added float constant collection/emission in `compiler.rb`
- Added FPU instructions (`fldl`, `fstpl`) to `emitter.rb`
- Float arithmetic operations are stubs (return self, 0, false)
- Result: Float literals compile without crashes, but most specs using floats also use `context`

**Operator/Method Stubs Added** (`lib/core/fixnum.rb`):
- Bitwise: `&`, `|`, `^`, `~`, `<<`, `>>` (stub implementations)
- Math: `**`, `-@`, `truncate`, `gcd`, `lcm`, `gcdlcm`, `ceildiv`
- Predicates: `even?`, `odd?` (mostly working)
- Result: 8+ specs moved from SEGFAULT to FAIL

**Rational Support** - PARTIAL
- Added `Rational` class (`lib/core/rational.rb`) - **HAS TYPO: "initizalize" → should be "initialize"**
- Added `Integer#numerator`, `Integer#denominator`, `Integer#to_r`
- Required in `lib/core/core.rb`

### 🐛 Known Bugs

#### Typo in Rational Class
**File**: `lib/core/rational.rb:3`
**Issue**: `def initizalize` should be `def initialize`
**Impact**: Rational objects can't be initialized properly

#### Parser Bugs
- `tokens.rb:383` - nil error triggered by `context` keyword usage
- `tokens.rb:320` - affects some specs (gcd_spec, lcm_spec, pow_spec)

## Critical Missing Language Features

### Exception Handling
- **Priority: High**
- Limited begin/rescue support
- No ensure blocks
- Basic infrastructure exists but commented out for bootstrap
- **File**: `driver.rb:45-50`

### Regular Expressions
- **Priority: High**
- No regex support at all
- Many Ruby libraries depend on regex
- **Workaround**: String manipulation methods only

### Dynamic Code Execution
- **Priority: Medium**
- No eval, no runtime code generation
- **Rationale**: Conflicts with ahead-of-time compilation model

### Lambda Syntax (->)
- **Priority: High**
- Stabby lambda `-> { }` not supported
- Blocks ~30+ modern Ruby specs
- Parser treats `->` as minus + greater-than

### Module System
- Include mechanism incomplete
- Constant resolution gaps
- Method precedence unclear (superclass vs eigenclass)

### Method Features
- Default arguments: Limited support
- Keyword arguments: Not implemented
- Method visibility (private/protected): Not supported
- alias/alias_method: Not implemented
- undef_method: Not implemented

## Segfault Issues (20 specs)

Most segfaults are due to:
1. Method not in vtable → `method_missing` → division by zero → SIGFPE
2. Specs using `.send(@method)` to call dynamically
3. Methods added to classes but not in vtable at compile time

**Affected specs**: bit_and_spec, bit_length_spec, size_spec, times_spec, and 16 others

## Architectural Issues

### Performance
- Simple mark-and-sweep GC inefficient for many small objects
- Excessive object creation during compilation
- No object pooling for frequently allocated types

### Code Generation
- No inlining - method calls always involve full dispatch
- Poor constant folding
- No dead code elimination
- Some assembly patterns suboptimal

### Register Allocation
- Simple allocator, opportunities for improvement
- Cross-call preservation needs work
- Naive spilling strategy

### Error Handling
- Poor error messages in many places
- Inconsistent error location reporting
- Limited error recovery in parser

## Testing Infrastructure

### Spec Helper Needs
- [x] Shared examples support - DONE
- [ ] `context` implementation - **CRITICAL BLOCKER**
- [ ] `be_kind_of` matcher
- [ ] `platform_is` guard
- [ ] Mock improvements
- [ ] `Object#Integer` method

### Test Coverage
- Self-test is minimal
- No comprehensive integration tests
- Bootstrap process requires manual verification

## Priority Assessment

### CRITICAL (blocks many specs)
1. **Implement `context` as alias for `describe`** - Would unblock ~29 compile failures immediately
2. Fix typo in Rational class
3. Add missing spec helper methods (be_kind_of, Integer, platform_is)
4. Implement require_relative or workaround

### HIGH (for robustness)
1. Exception handling (begin/rescue/ensure)
2. Lambda syntax (`->`)
3. Fix vtable/method_missing issues causing segfaults
4. Better error reporting

### MEDIUM (for feature completeness)
1. Regular expressions
2. Full Float arithmetic (not just literals)
3. Complete object model features
4. Advanced optimizations

## Development Process

### Build System
- All builds require Docker (i386 environment)
- Some manual steps not automated
- Platform specific (x86 32-bit)

### Debugging
- Basic STABS support only
- Assembly debugging challenging
- Difficult to track down segfaults

### Documentation
- Architecture docs limited
- Many interfaces undocumented
- Inconsistent commenting

---

**Note**: For historical information about fixed bugs, see FIXED-ISSUES.md
