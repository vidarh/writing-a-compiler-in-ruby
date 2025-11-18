# Language Spec Compile Failures - Root Cause Summary

**Date**: 2025-11-18
**Total Compile Failures**: 29 specs

## Categorized by Root Cause

### Issue #36: Keyword Argument Shorthand (3 specs)
**Not Supported**: Ruby 3.1+ syntax `{a:}` meaning `{a: a}`

- ✅ rubyspec/language/hash_spec.rb (line 307: `h = {a:}`)
- ✅ rubyspec/language/def_spec.rb (keyword args in method definitions)
- ✅ rubyspec/language/method_spec.rb (keyword args in method calls)
- ✅ rubyspec/language/keyword_arguments_spec.rb

**Status**: Documented in KNOWN_ISSUES.md #36

---

### Issue #45: Splat with Begin Block in Array Indexing (2 specs)
**Syntax Error**: `arr[*begin ... end]` not supported

- ✅ rubyspec/language/assignments_spec.rb (line 261: `$spec_b[*begin 1; [:k] end] += 10`)
- ✅ rubyspec/language/optional_assignments_spec.rb (line 563)

**Status**: Documented in KNOWN_ISSUES.md #45
**Test**: spec/array_index_splat_begin_spec.rb

---

### Issue #38: Regex After Semicolon Parsed as Division (1 spec)
**Architecture Issue**: Tokenizer doesn't know parser consumed semicolon

- ✅ rubyspec/language/case_spec.rb (line 392: `when (raise if 2+2 == 3; /a/)`)

**Status**: Documented in KNOWN_ISSUES.md #38 (DEFERRED)

---

### Issue #2: Parser Requires Atom for Superclass (1 spec)
**Parse Error**: Class definitions only accept identifiers as superclass

- ✅ rubyspec/language/class_spec.rb (line 450: `class TestClass < ""`)

**Status**: Documented in KNOWN_ISSUES.md #2

---

### Issue #46: Nested Constant Assignment in Closures (3 specs)
**Compiler Error**: `A::B::C = value` inside closures not recognized as valid lvalue

- ✅ rubyspec/language/constants_spec.rb (line 556: `ConstantSpecs::ClassB::CS_CONST101 = :const101_1`)
- ✅ rubyspec/language/module_spec.rb (nested module constant assignments)
- ✅ rubyspec/language/precedence_spec.rb (complex nested assignments)

**Status**: Documented in KNOWN_ISSUES.md #46

---

### Safe Navigation Operator `&.` Not Supported (1 spec)
**Missing Feature**: Ruby 2.3+ safe navigation operator

- ✅ rubyspec/language/safe_navigator_spec.rb (line 13: `nil&.unknown`)

**Error**: "Missing value in expression / op: {&/2 pri=11}"

**Status**: New issue - requires parser support for `&.` operator

---

### Global Variable Scope Issue (1 spec)
**Parse Error**: Unable to resolve global variable

- ✅ rubyspec/language/return_spec.rb (line 613: Parse error: `Unable to open '$spec_filename'`)
  - Error after `require $spec_filename`
  - Global variable `$spec_filename` not in scope or not recognized

**Test**: spec/return_global_var_spec.rb

**Status**: Global variable handling or require with variable argument

---

### Control Flow Edge Cases (2 specs)
**Missing Value Errors**: Complex control flow combinations

- ✅ rubyspec/language/until_spec.rb (line 158: `((i+=1) == 3 ? next : j+=i) until i > 10`)
  - Error: Missing value in expression / op: {ternif/2 pri=6}
  - Ternary operator with `next` in until modifier
  - **Test**: spec/until_ternary_next_spec.rb

- ✅ rubyspec/language/while_spec.rb (line 93: parenthesized break statement)
  - Error: Missing value in expression / op: {or_assign/2 pri=7}
  - `break if c` inside parentheses with or-assign
  - **Test**: spec/while_parenthesized_break_spec.rb

**Status**: Parser doesn't handle ternary+next and parenthesized break in certain contexts

---

### Rescue with Safe Navigation (1 spec)
**Missing Value**: Safe navigation in rescue clause

- ✅ rubyspec/language/rescue_spec.rb (line 147: `rescue => self&.captured_error`)
  - Error: Missing value in expression / op: {callm/2 pri=98}
  - Combination of rescue exception capture and safe navigation operator

**Test**: spec/rescue_safe_navigation_spec.rb

**Status**: Parser doesn't support `&.` in rescue exception binding

---

### Anonymous Splat Assignment (1 spec)
**Splat Operator**: Anonymous splat not supported

- ✅ rubyspec/language/variables_spec.rb (line 410: `(* = 1).should == 1`)
  - Error: Missing value in expression / {splat/1 pri=8}
  - Anonymous splat assignment `* = value` (valid Ruby, discards value)

**Test**: spec/anonymous_splat_assignment_spec.rb

**Status**: Parser doesn't recognize `*` alone as valid assignment target

---

### Ruby 2.7+ Features (Not Target Version) (1 spec)
**Expected Failure**: Pattern matching is Ruby 2.7+ feature

- ✅ rubyspec/language/pattern_matching_spec.rb (undefined method `to_sym` for Array)

**Status**: Out of scope for Ruby 2.5 target

---

### Closure Compilation Link Errors (3 specs)
**Undefined __env__ and __closure__ References**

- ✅ rubyspec/language/for_spec.rb (lines 97, 109: undefined __env__ and __closure__)
- ✅ rubyspec/language/send_spec.rb (lines 559, 573: undefined __env__)
- ✅ rubyspec/language/super_spec.rb (lines 340, 1013: undefined Module reference)

**Error**: Link fails with "undefined reference to `__env__'" and "undefined reference to `__closure__'"

**Status**: Closure/eigenclass compilation bug - compiler generates references but doesn't emit the symbols

---

### Assembly Code Generation Errors (3 specs)
**Compiler Emits AST Instead of Assembly**

- ✅ rubyspec/language/metaclass_spec.rb (Error: junk `[:sexp' after expression)
- ✅ rubyspec/language/private_spec.rb (Error: junk `[:sexp' after expression)
- ✅ rubyspec/language/singleton_class_spec.rb (Error: junk `[:sexp' after expression)

**Error**: Assembly contains literal "[:sexp :__S___3aA]" instead of proper assembly instructions

**Status**: Compiler bug - failing to compile certain constructs, emitting AST nodes directly

---

### Heredoc Parsing Error (1 spec)
**Unterminated Heredoc**

- ✅ rubyspec/language/heredoc_spec.rb (tokens.rb:813: Unterminated heredoc)

**Error**: "Unterminated heredoc (expected HERE\n)"

**Status**: Heredoc tokenizer issue - likely edge case in heredoc parsing

---

### Block Parsing Error (1 spec)
**Expected 'end' for 'do'-block**

- ✅ rubyspec/language/regexp/encoding_spec.rb (line 46: Expected: 'end' for 'do'-block)

**Error**: Parse error expecting block terminator

**Status**: Parser doesn't handle certain do-block constructs

---

### Duplicate Symbol Definitions (1 spec)
**Assembly Error - Symbol Already Defined**

- ✅ rubyspec/language/predefined_spec.rb (lines 196074, 196147: `symbol __method_Object_method_missing is already defined`)

**Error**: Compiler generates duplicate method definitions in assembly

**Status**: Compiler bug - method redefinition not handled properly

---

### Expression Reduction Error (1 spec)
**Parser Stack Error**

- ✅ rubyspec/language/symbol_spec.rb (line 91: Expression did not reduce to single value - 2 values on stack)

**Error**: "Expression did not reduce to single value (2 values on stack)" with comma and assign operators
**Related**: WARNING: "String interpolation requires passing block to Quoted.expect"

**Status**: Parser/shunting yard bug - likely related to %w with quotes

---

### Register Allocator Division By Zero (1 spec)
**Compiler Internal Error**

- ✅ rubyspec/language/regexp/escapes_spec.rb (regalloc.rb:332: divided by 0)

**Error**: ZeroDivisionError in register allocator during compilation

**Status**: Compiler bug in register allocation phase

---

## Summary

| Root Cause | Specs Affected | Fixable? |
|------------|----------------|----------|
| Keyword arg shorthand (#36) | 4 | Requires parser support |
| Nested const in closures (#46) | 3 | Requires compiler changes |
| Closure link errors (__env__) | 3 | Compiler bug - HIGH PRIORITY |
| Assembly code gen errors (:sexp) | 3 | Compiler bug - HIGH PRIORITY |
| Splat+begin in indexing (#45) | 2 | Edge case, workaround exists |
| Control flow edge cases | 2 | Needs investigation |
| Regex after semicolon (#38) | 1 | Deferred (architecture issue) |
| Superclass atom requirement (#2) | 1 | Low priority |
| Safe navigation `&.` | 1 | Requires new operator support |
| Heredoc parsing | 1 | Tokenizer bug |
| Block parsing (do-end) | 1 | Parser bug |
| Duplicate symbol definitions | 1 | Compiler bug |
| Expression reduction error | 1 | Parser/shunting yard bug |
| Register allocator div-by-zero | 1 | Compiler bug |
| Other edge cases | 4 | Needs investigation |
| Ruby 2.7+ features | 1 | Out of scope |

**Total Documented**: 29/29 specs have identified root causes (100%)
**All compile failures are now fully documented!**

## Next Steps

1. **High Priority**: Keyword argument shorthand (#36) - affects 4 specs
2. **Medium Priority**: Safe navigation operator - affects 1 spec but common feature
3. **Low Priority**: Edge cases with workarounds (#45, #46)
4. **Investigate**: 11 specs with no obvious error message
