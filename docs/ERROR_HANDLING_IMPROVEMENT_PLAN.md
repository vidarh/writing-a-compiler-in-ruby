# Error Handling Improvement Plan (Session 41)

## Status

**PARTIALLY COMPLETE**: treeoutput.rb reverted to original simple error messages

**REMAINING**: Add multi-line source context to ALL error messages

---

## Context Collection Strategy

### Problem
Error messages need to show multiple lines of source code around the error location with a visual pointer to the exact column.

### Available Information

**From Scanner/Parser**:
- `@scanner.position` - returns Position object with filename, lineno, col
- `@scanner.filename` - file path
- `@scanner.lineno` - current line number (integer)
- `@scanner.col` - current column number (integer)

**From TreeOutput (Shunting Yard)**:
- Currently NO access to scanner
- Need to add scanner reference

### Solution Architecture

#### 1. Shared Helper Method (parserbase.rb)

**Location**: parserbase.rb (class method, can be called from anywhere)

**Method signature**:
```ruby
def self.format_source_context(filename, lineno, col, lines_before=3, lines_after=2)
```

**How it collects context**:
```
1. Check if filename is a real file (File.exist?(filename))
   - If not a file (e.g., "<stream>"), return empty string

2. Read entire file into memory:
   all_lines = File.readlines(filename)

3. Calculate line range:
   start_line = [lineno - lines_before, 1].max
   end_line = [lineno + lines_after, all_lines.length].min

4. Build context array with line numbers and markers:
   - Loop from start_line to end_line
   - For each line:
     - Get line content: all_lines[line_num - 1].chomp
     - Add marker: ">" for error line, " " for context lines
     - Format as: sprintf("%s %4d | %s", marker, line_num, line)
   - After error line, add column pointer:
     - Calculate spaces needed: " " * (7 + col)
     - Add "^" character

5. Join with newlines and return
```

**Why this approach**:
- Simple: Re-reads file on error (happens rarely, so performance OK)
- Works for files only (not streams, but that's rare in practice)
- No need to buffer lines in scanner (avoids memory overhead)
- Can be called from both parser and shunting yard

**Example output**:
```
     2 | def foo(x)
     3 |   result = case x
     4 |   when 1
>    5 |   when 2 .should
               ^
     6 |   when 3
     7 |     :three
```

**Edge cases handled**:
- Lines near start of file (can't show 3 lines before line 2)
- Lines near end of file (can't show 2 lines after last line)
- File doesn't exist (return empty string, fall back to no context)
- Streams (filename = "<stream>", no context available)
- Very long lines (truncate to 120 chars if needed? - TBD)

#### 2. Pass Scanner to TreeOutput

**Why needed**: TreeOutput (shunting yard errors) needs access to scanner position for context

**Changes in shunting.rb**:
```ruby
# In initialize method (line ~13):
def initialize(output, tokenizer, parser, inhibit = [])
  @output = output
  @tokenizer = TokenizerAdapter.new(tokenizer,parser)
  @parser = parser

  # NEW: Pass scanner reference to output
  if @output.respond_to?(:set_scanner)
    # TokenizerAdapter wraps Tokens::Tokenizer which has @scanner
    scanner = tokenizer.instance_variable_get(:@scanner) if tokenizer.respond_to?(:instance_variable_get)
    @output.set_scanner(scanner) if scanner
  end

  # ... rest of method
end
```

**Changes in treeoutput.rb**:
```ruby
# Add new method:
def set_scanner(scanner)
  @scanner = scanner
  @filename = scanner.filename if scanner
end

# Now oper() and result() can use @scanner and @filename
```

**Alternative approach** (if instance_variable_get doesn't work in self-hosted compiler):
- Add `scanner` accessor to TokenizerAdapter
- Add `scanner` accessor to Tokens::Tokenizer
- Pass through chain: Tokenizer → TokenizerAdapter → TreeOutput

#### 3. Error Message Format

**All error messages follow same structure**:

```
[ERROR TYPE]: [FILE]:[LINE]:[COL]: [MESSAGE]

[3 LINES OF CONTEXT BEFORE]
> [ERROR LINE]
        ^
[2 LINES OF CONTEXT AFTER]

[TECHNICAL DETAILS - ALL VISIBLE, NO HIDING]
```

**Example parser error**:
```
Parse error: test.rb:5:10: Expected: 'end' for open 'case'

     2 | def foo(x)
     3 |   result = case x
     4 |   when 1
>    5 |   when 2 .should
               ^
     6 |   when 3
     7 |     :three

Next characters: ' .should\n  when 3\n    :three\n'
```

**Example shunting yard error**:
```
Shunting yard error: test.rb:5:12: Binary operator missing left operand

     2 | def foo(x)
     3 |   result = case x
     4 |   when 1
>    5 |   when 2 .should
                 ^
     6 |   when 3
     7 |     :three

Operator: #<OpPrec::Op @sym=:callm, @type=:prefix, @arity=2, @minarity=2, @pri=99>
  symbol=:callm, type=:prefix, arity=2/2, priority=99
Value stack (1): [[:when, 2, nil]]
Right operand: :should
```

---

## Implementation Steps

### Step 1: ✅ COMPLETE - Revert treeoutput.rb
- Removed all helper methods from commit 33914d0
- Restored oper() to original simple error messages
- Restored result() to original simple error message

### Step 2: Revert parserbase.rb
- Restore error() method to original (with "After: " context)
- Remove COMPILER_DEBUG gating

### Step 3: Add format_source_context helper
- Add as class method to ParserBase
- Implement file reading and context formatting
- Test with various line numbers (start, middle, end of files)

### Step 4: Improve parserbase.rb error() method
- Call format_source_context() to get multi-line context
- Keep "Next characters" output (original behavior)
- Show ALL details, no hiding

### Step 5: Add scanner to TreeOutput
- Modify shunting.rb initialize to pass scanner
- Add set_scanner method to TreeOutput
- Store @scanner and @filename

### Step 6: Improve TreeOutput error messages
- Modify oper() to call format_source_context()
- Modify result() to call format_source_context()
- Show ALL technical details (operator, value stack, etc.)
- No hiding behind environment variables

### Step 7: Testing
- Create test file with deliberate errors
- Verify all error types show multi-line context
- Verify column pointer accuracy
- Run make selftest (must pass)

---

## Testing Plan

### Test File 1: Parser Errors (test_parser_errors.rb)
```ruby
def foo
  case x
  when 1
    :one
  # Missing 'end' keyword - should show context

def bar
  # This will cause error at line 5
end
```

### Test File 2: Shunting Yard Errors (test_shunting_errors.rb)
```ruby
def foo
  x = 1 +
  # Missing right operand - should show context
end

def bar
  result = case 1
  when 1
    :foo
  end.should
  # Method call on case expression - may cause shunting yard error
end
```

### Expected Behavior
- Each error shows 3 lines before + error line + 2 lines after
- Column pointer (^) points to exact error position
- All operator/token details visible
- File:line:column in standard format

---

## Risks and Mitigations

**Risk 1**: File.readlines() may not work in self-hosted compiler
- Mitigation: Test early, have fallback to no-context if fails

**Risk 2**: instance_variable_get may not work
- Mitigation: Add proper accessors instead

**Risk 3**: Very long lines may break formatting
- Mitigation: Truncate lines > 120 chars with "..." suffix

**Risk 4**: Binary files or encoding issues
- Mitigation: Wrap File.readlines in begin/rescue, return empty on error

---

## Success Criteria

✓ All error messages show multi-line source context
✓ Column pointer (^) shows exact error position
✓ File:line:column in standard format
✓ ALL technical details visible (no COMPILER_DEBUG hiding)
✓ Works for both parser and shunting yard errors
✓ make selftest passes with 0 failures
✓ Error quality dramatically better than original
