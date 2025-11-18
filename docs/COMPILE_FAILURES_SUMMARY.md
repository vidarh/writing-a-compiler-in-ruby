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

### Global Variable / Special Cases (1 spec)
**Parse Error**: Unable to resolve special file variable

- ✅ rubyspec/language/return_spec.rb (line 613: `Unable to open '$spec_filename'`)

**Status**: May be fixture loading issue or special global var handling

---

### Control Flow Edge Cases (2 specs)
**Missing Value Errors**: Complex control flow combinations

- ✅ rubyspec/language/until_spec.rb (line 158: ternary with next)
- ✅ rubyspec/language/while_spec.rb (line 93: or_assign with if/break)

**Status**: Edge cases in control flow parsing - need individual investigation

---

### Rescue Operator Edge Case (1 spec)
**Missing Value**: Safe navigation in rescue clause

- ✅ rubyspec/language/rescue_spec.rb (line 147: likely `rescue => self&.var`)

**Status**: Combination of rescue and safe navigation

---

### Variables / Splat Issues (1 spec)
**Splat Operator**: Edge case with splat usage

- ✅ rubyspec/language/variables_spec.rb (line 410: splat operator issue)

**Status**: Needs investigation

---

### Ruby 2.7+ Features (Not Target Version) (1 spec)
**Expected Failure**: Pattern matching is Ruby 2.7+ feature

- ✅ rubyspec/language/pattern_matching_spec.rb (undefined method `to_sym` for Array)

**Status**: Out of scope for Ruby 2.5 target

---

### No Obvious Parse Error (11 specs)
**May Compile or Have Other Issues**:

- rubyspec/language/for_spec.rb
- rubyspec/language/heredoc_spec.rb
- rubyspec/language/metaclass_spec.rb
- rubyspec/language/predefined_spec.rb
- rubyspec/language/private_spec.rb
- rubyspec/language/send_spec.rb
- rubyspec/language/singleton_class_spec.rb
- rubyspec/language/super_spec.rb
- rubyspec/language/symbol_spec.rb
- rubyspec/language/regexp/encoding_spec.rb
- rubyspec/language/regexp/escapes_spec.rb

**Status**: Need individual investigation - may have runtime issues or pass

---

## Summary

| Root Cause | Specs Affected | Fixable? |
|------------|----------------|----------|
| Keyword arg shorthand (#36) | 4 | Requires parser support |
| Splat+begin in indexing (#45) | 2 | Edge case, workaround exists |
| Regex after semicolon (#38) | 1 | Deferred (architecture issue) |
| Superclass atom requirement (#2) | 1 | Low priority |
| Nested const in closures (#46) | 3 | Requires compiler changes |
| Safe navigation `&.` | 1 | Requires new operator support |
| Control flow edge cases | 2 | Needs investigation |
| Other edge cases | 4 | Needs investigation |
| Ruby 2.7+ features | 1 | Out of scope |
| Unknown / may pass | 11 | Needs investigation |

**Total Documented**: 18/29 specs have identified root causes
**Total Needing Investigation**: 11 specs

## Next Steps

1. **High Priority**: Keyword argument shorthand (#36) - affects 4 specs
2. **Medium Priority**: Safe navigation operator - affects 1 spec but common feature
3. **Low Priority**: Edge cases with workarounds (#45, #46)
4. **Investigate**: 11 specs with no obvious error message
