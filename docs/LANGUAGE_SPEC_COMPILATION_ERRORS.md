# Language Spec Compilation Error Analysis

**Purpose**: Categorize compilation errors in language specs to prioritize fixes
**Goal**: Make specs COMPILE first (passing tests is secondary)
**Sampled**: 17 specs across all 6 categories from LANGUAGE_SPEC_ANALYSIS.md

---

## Error Categories (Prioritized by Impact)

### 1. Parser Internal Bug - `position=` Method (HIGH PRIORITY - Actual Bug)

**Affected specs**: break_spec.rb, string_spec.rb (and likely many others)

**Error**:
```
undefined method `position=' for #<Scanner:0x...>
Did you mean?  position
```

**Root cause**: Parser code at `parser.rb:405` calls `scanner.position = ...` but Scanner only has `position` (getter), not `position=` (setter).

**Impact**: CRITICAL - this is an actual compiler bug that affects many specs

**Fix priority**: **HIGHEST** - fix this first, will unblock many specs

**Estimated complexity**: LOW - add setter method to Scanner class

**Files**: scanner.rb, tokens.rb (Scanner class definition)

---

### 2. Argument Parsing - Splat and Keyword Arguments (HIGH IMPACT)

**Affected specs**: def_spec.rb, keyword_arguments_spec.rb, block_spec.rb

**Error**:
```
Expected: argument name following '*'
```

**Root cause**: Parser doesn't support:
- Bare splat operator: `def foo(*); end` (catches all args without naming)
- Keyword splat: `def foo(**kwargs); end`
- Block argument splat: `foo(*args, &block)`

**Impact**: HIGH - blocks many method definition specs

**Fix priority**: HIGH - needed for advanced method definitions

**Estimated complexity**: MEDIUM - need to extend argument parser

**Files**: parser.rb (parse_arglist method around line 52)

**Example failures**:
- `def foo(*); end` - bare splat
- `def foo(**kwargs); end` - keyword splat
- Method calls with splat: `foo(*args)`

---

### 3. Begin/Rescue/Ensure Block Parsing (HIGH IMPACT)

**Affected specs**: rescue_spec.rb, ensure_spec.rb, return_spec.rb

**Error**:
```
Expected: 'end' for open 'begin' block
```

**Root cause**: Parser doesn't support:
- `else` clause in rescue blocks: `begin ... rescue ... else ... end`
- `ensure` blocks: `begin ... ensure ... end`
- Multiple rescue clauses with types: `rescue FooError ... rescue BarError ...`

**Impact**: HIGH - exception handling is a core feature

**Fix priority**: HIGH - many specs use rescue/ensure

**Estimated complexity**: MEDIUM-HIGH - need to extend begin/rescue parser

**Files**: parser.rb (parse_begin method around line 266)

**Example failures**:
```ruby
begin
  # code
rescue
  # error handler
else
  # no error clause - NOT SUPPORTED
end

begin
  # code
ensure
  # cleanup - NOT SUPPORTED
end
```

---

### 4. Shunting Yard Expression Parsing (MEDIUM-HIGH IMPACT)

**Affected specs**: if_spec.rb, case_spec.rb, class_spec.rb, block_spec.rb

**Error types**:
```
Missing value in expression / op: {callm/2 pri=98} / vstack: [] / rightv: :should
Missing value in expression / op: {deref/2 pri=100} / vstack: [] / rightv: :Foo
Incomplete expression - [[:splat, ...], [:to_block, ...]]
```

**Root cause**: Shunting yard parser gets confused by:
- Method calls at specific positions (after blocks, before operators)
- Dereferencing constants in certain contexts
- Splat operators in expressions
- Block-to-proc conversions

**Impact**: MEDIUM-HIGH - affects many core language features

**Fix priority**: MEDIUM - complex interactions, needs careful analysis

**Estimated complexity**: HIGH - shunting yard is complex, may have multiple root causes

**Files**: shunting.rb, treeoutput.rb

**Note**: These may be multiple distinct bugs that manifest as shunting yard errors. Need to investigate each case individually.

**IMPORTANT - Error Reporting**:
- Current errors are cryptic and hard to debug
- Need BOTH human-readable output AND optional technical debug mode
- Human-readable: "Expected value after method call" with code context
- Technical mode: Show operator stack, value stack, current token, operator priorities
- Can now use exceptions for error handling (self-hosted compiler supports it)

---

### 5. Multiple Assignment / Destructuring (MEDIUM IMPACT)

**Affected specs**: and_spec.rb, or_spec.rb

**Error**:
```
Compiler error: Expected an argument on left hand side of assignment - got subexpr
(left: [[:index, :__env__, 1], :false, [:index, :__env__, 2]], right: [:callm, :__destruct, :[], [[:sexp, 5]]])
```

**Root cause**: Compiler doesn't support:
- Multiple assignment: `a, b, c = [1, 2, 3]`
- Destructuring in boolean expressions
- Parallel assignment

**Impact**: MEDIUM - many specs use multiple assignment

**Fix priority**: MEDIUM - common Ruby idiom

**Estimated complexity**: MEDIUM-HIGH - need to implement destructuring compilation

**Files**: compiler.rb (compile_assign method around line 603)

**Example failures**:
```ruby
a, b = [1, 2]  # NOT SUPPORTED
x, *rest = array  # NOT SUPPORTED
```

---

### 6. Lambda/Proc Brace Syntax (MEDIUM IMPACT)

**Affected specs**: lambda_spec.rb, proc_spec.rb

**Error**:
```
Expected: do .. end block
```

**Root cause**: Brace syntax likely HAS BUGS or LIMITATIONS (not fully unsupported)
- Parser likely supports `{ }` in some contexts but not others
- May have precedence issues or context-sensitive bugs
- Need to investigate where braces work vs. where they fail

**Impact**: MEDIUM - both syntaxes are common in Ruby

**Fix priority**: MEDIUM - investigate actual limitations first

**Estimated complexity**: MEDIUM - needs investigation to find actual bugs

**Files**: parser.rb (parse_lambda method around line 286)

**Example failures**:
```ruby
lambda { |x| x + 1 }  # May have issues
->arg { var = arg }   # Stabby lambda with braces
```

**Action**: Test brace syntax in various contexts to identify actual bugs/limitations

---

### 7. Heredoc Parsing (LOW-MEDIUM IMPACT)

**Affected specs**: heredoc_spec.rb

**Error**:
```
Unterminated heredoc (expected HERE\n)
```

**Root cause**: Heredoc parser has issues with:
- Indented heredocs (`<<~HERE`)
- Heredocs with interpolation
- Multiple heredocs in one expression
- Heredoc terminator matching

**Impact**: LOW-MEDIUM - heredocs are common but have workarounds

**Fix priority**: MEDIUM - useful feature but not blocking

**Estimated complexity**: MEDIUM - heredoc parsing is notoriously tricky

**Files**: tokens.rb (get_raw method around line 538)

---

### 8. String/Symbol Parsing Edge Cases (LOW-MEDIUM IMPACT)

**Affected specs**: hash_spec.rb, string_spec.rb, symbol_spec.rb

**Error**:
```
Unterminated string
```

**Root cause**: String parser issues with:
- Escaped quotes in specific contexts
- String interpolation edge cases
- Symbol literals with special characters
- Hash syntax with symbols as keys

**Impact**: LOW-MEDIUM - basic strings work, edge cases fail

**Fix priority**: MEDIUM - affects hash literals and symbols

**Estimated complexity**: MEDIUM - quote/escape handling is subtle

**Files**: quoted.rb (expect_squoted method around line 105)

---

### 9. Missing Exception Classes (LOW IMPACT - Link Failure)

**Affected specs**: loop_spec.rb (and potentially others)

**Error**:
```
undefined reference to 'NameError'
```

**Root cause**: Code compiles and assembles successfully but fails at link time because exception classes are not implemented:
- NameError
- NoMethodError
- ArgumentError (may be implemented)
- etc.

**Impact**: LOW - specs compile, just need exception class stubs

**Fix priority**: LOW - easy to add stubs when needed

**Estimated complexity**: LOW - create stub exception classes

**Files**: lib/core/exception.rb (add missing exception class definitions)

**Note**: This is NOT a parser/compiler issue - just missing library code. Specs COMPILE successfully, they just can't run yet.

---

## Recommended Fix Order

### Phase 1: Parser Bug Fixes (Highest Priority)
1. **Fix Scanner#position= bug** (parser.rb:405, scanner.rb)
   - Add setter method
   - Test with break_spec.rb and string_spec.rb
   - Expected impact: May unblock 5-10 specs immediately

### Phase 2: Core Language Features
2. **Add else clause to rescue** (parser.rb parse_begin)
   - Extend begin/rescue parser
   - Test with rescue_spec.rb

3. **Add ensure block support** (parser.rb parse_begin)
   - Extend begin/rescue parser
   - Test with ensure_spec.rb

### Phase 3: Advanced Argument Parsing
4. **Support bare splat operator** (parser.rb parse_arglist)
   - `def foo(*); end`
   - Test with def_spec.rb

5. **Support keyword splat** (parser.rb parse_arglist)
   - `def foo(**kwargs); end`
   - Test with keyword_arguments_spec.rb

### Phase 4: Expression Parsing Improvements
6. **Investigate shunting yard errors** (shunting.rb, treeoutput.rb)
   - Create minimal test cases for each error type
   - Fix one at a time
   - Test with if_spec.rb, case_spec.rb, class_spec.rb

### Phase 5: Nice-to-Have Features
7. **Lambda brace syntax** (parser.rb parse_lambda)
8. **Heredoc improvements** (tokens.rb)
9. **Multiple assignment** (compiler.rb compile_assign)

---

## Error Reporting Improvements Needed

Before fixing these issues, improve error messages:

1. **Parser errors should show**:
   - Exact line and column number
   - Surrounding context (3-5 lines)
   - What was expected vs. what was found
   - Suggestion for common mistakes

2. **Shunting yard errors should show**:
   - The expression being parsed
   - The operator stack state
   - Which operator caused the issue
   - What values were on the value stack

3. **Compiler errors should show**:
   - The AST node being compiled
   - The parent context
   - Suggestions for what syntax IS supported

---

## Summary Statistics

**Total specs sampled**: 17
- **Parser bugs**: 2 specs (break, string) - Scanner#position=
- **Argument parsing**: 3 specs (def, keyword_arguments, block)
- **Begin/rescue/ensure**: 3 specs (rescue, ensure, return)
- **Shunting yard**: 4 specs (if, case, class, block)
- **Assignment**: 2 specs (and, or)
- **Lambda syntax**: 1 spec (lambda)
- **Heredoc**: 1 spec (heredoc)
- **String parsing**: 1 spec (hash)
- **Link failures**: 1 spec (loop) - not a parser issue

**Quick wins** (if we fix Scanner#position= bug):
- Potentially 5-10 specs may compile immediately
- Would reduce compile failure rate from 91% significantly

**Medium effort, high impact**:
- Begin/rescue/ensure support: ~10-15 specs
- Argument parsing (splat/keywords): ~5-10 specs

**Long-term improvements**:
- Shunting yard fixes: gradual improvement across many specs
- Multiple assignment: ~5-10 specs
