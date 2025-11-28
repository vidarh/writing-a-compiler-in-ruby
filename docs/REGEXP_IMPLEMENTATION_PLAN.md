# Regexp Implementation Plan

This document outlines a phased approach to implementing regular expression support in the Ruby compiler, starting from the most basic functionality and building toward full Ruby Regexp compatibility.

---

## Current Status

**Last Updated**: 2025-11-28

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 0: Quick Wins | ✅ COMPLETE | source, options, inspect, to_s, escape, union |
| Phase 1: Literal Matching | ✅ COMPLETE | Exact string matching |
| Phase 2: Metacharacters | ✅ COMPLETE | `.`, `^`, `$`, escape sequences |
| Phase 3: Character Classes | ✅ COMPLETE | `[abc]`, `[a-z]`, `[^abc]`, `\d`, `\w`, `\s` |
| Phase 4: Quantifiers | ✅ COMPLETE | `*`, `+`, `?`, `{n,m}`, non-greedy `*?`, `+?`, `??` |
| Phase 5: Groups/Alternation | ✅ COMPLETE | `(...)` grouping, `|` alternation, capture groups |
| Phase 6: NFA/DFA | ❌ NOT STARTED | Performance optimization |
| Phase 7: Ruby-Specific | ❌ NOT STARTED | Lookahead, backreferences, etc. |

**Test Results**:
- Regexp core specs: 42% (66/154 passing)
- Language specs: ~21% (pending full retest)
- Both selftest and selftest-c pass

---

## TODO: Next Steps (Priority Order)

1. ~~Capture groups with MatchData#[] support~~ ✅ DONE
2. ~~Case-insensitive matching (IGNORECASE flag)~~ ✅ DONE
3. ~~Word boundaries `\b`, `\B`~~ ✅ DONE
4. ~~String#scan using regexp~~ ✅ DONE
5. ~~String#gsub using regexp~~ ✅ DONE
6. ~~String#split with regexp~~ ✅ DONE
7. ~~Multiline mode (MULTILINE flag)~~ ✅ DONE
8. Named captures (?<name>...) (blocked by self-hosting bug #57)
9. ~~Backreferences \1, \2, etc.~~ ✅ DONE
10. POSIX character classes (blocked by self-hosting bug #56)

---

## Phase 0: Quick Wins (No Matching Required) - ✅ COMPLETE

**Goal**: Pass regexp specs that test Regexp class behavior, NOT matching.

Many rubyspec tests just verify that Regexp objects have certain methods and properties. These can pass without implementing any actual matching!

### Current State

The existing `lib/core/regexp.rb` is minimal:
```ruby
class Regexp
  IGNORECASE = 1
  EXTENDED = 2
  MULTILINE = 4

  def initialize(arg); end
  def =~(string); nil; end
end
```

### Quick Win #1: Store and Return Source

**Effort**: 5 minutes
**Specs Fixed**: ~16 in source_spec.rb

```ruby
class Regexp
  attr_reader :source, :options

  def initialize(pattern, options = 0)
    @source = pattern.is_a?(Regexp) ? pattern.source : pattern.to_s
    @options = options.is_a?(Integer) ? options : 0
  end
end
```

### Quick Win #2: Basic Inspection Methods

**Effort**: 10 minutes
**Specs Fixed**: ~10+ in inspect_spec.rb, to_s_spec.rb

```ruby
class Regexp
  def inspect
    "/#{@source}/"
  end

  def to_s
    "(?-mix:#{@source})"
  end

  def ==(other)
    other.is_a?(Regexp) && @source == other.source && @options == other.options
  end
  alias eql? ==

  def hash
    @source.hash ^ @options.hash
  end

  def casefold?
    (@options & IGNORECASE) != 0
  end
end
```

### Quick Win #3: Class Methods

**Effort**: 15 minutes
**Specs Fixed**: ~20+ in escape_spec.rb, quote_spec.rb, compile_spec.rb

```ruby
class Regexp
  def self.escape(str)
    # Escape regexp metacharacters
    str.to_s.gsub(/([.?*+^$\[\]\\(){}|\-])/, '\\\\\1')
  end
  class << self
    alias quote escape
  end

  def self.compile(pattern, options = 0)
    new(pattern, options)
  end

  def self.union(*patterns)
    return /(?!)/ if patterns.empty?
    patterns.map { |p| p.is_a?(Regexp) ? p.source : escape(p) }.join("|")
  end

  def self.last_match
    $~
  end

  def self.last_match=(match)
    $~ = match
  end
end
```

### Quick Win #4: Options Constants and Methods

**Effort**: 5 minutes
**Specs Fixed**: ~10 in options_spec.rb

```ruby
class Regexp
  IGNORECASE = 1
  EXTENDED = 2
  MULTILINE = 4
  FIXEDENCODING = 16
  NOENCODING = 32

  def options
    @options
  end

  def encoding
    # Stub: return default encoding
    Encoding::UTF_8
  end

  def fixed_encoding?
    (@options & FIXEDENCODING) != 0
  end
end
```

### Quick Win #5: Named Captures Stubs

**Effort**: 5 minutes
**Specs Fixed**: ~5 in named_captures_spec.rb, names_spec.rb

```ruby
class Regexp
  def names
    []  # Stub: no named captures support yet
  end

  def named_captures
    {}  # Stub: no named captures support yet
  end
end
```

### Quick Win Summary

| Enhancement | Time | Specs Fixed |
|------------|------|-------------|
| source/options | 5 min | ~16 |
| inspect/to_s/==/hash | 10 min | ~15 |
| escape/quote/compile/union | 15 min | ~20 |
| options constants | 5 min | ~10 |
| named_captures stubs | 5 min | ~5 |
| **Total** | **~40 min** | **~66 specs** |

### Implementation Priority

1. `source` and `options` - Most specs need these
2. `inspect` and `to_s` - Many specs print regexps
3. `==` and `hash` - Required for comparisons
4. `escape`/`quote` - Used by many Ruby programs
5. Named captures stubs - Returns empty, but won't crash

---

## Overview

### Goals
1. Start with minimal, working implementation
2. Each phase should be self-contained and testable
3. Architecture should allow progressive enhancement
4. Eventually support DFA/NFA compilation for performance

### Key Decision: Pure Ruby Implementation

**CRITICAL CONSTRAINT**: All regex implementation must be in pure Ruby with minimal s-expressions.
No C code, no assembly - the implementation must be self-hosting.

**Strategy: Ruby Interpreter with AOT Compilation**
- Write the regex engine entirely in Ruby
- Parse regex patterns to an IR (intermediate representation)
- Match using a Ruby-based NFA/DFA interpreter
- For literal patterns, compiler MAY generate inline matching code as s-expressions
- Dynamic patterns (`Regexp.new(string)`) use the Ruby interpreter at runtime

**Benefits of Pure Ruby:**
- Self-hosting: compiler can compile its own regex engine
- Portable: no platform-specific code
- Testable: can run under MRI for verification
- Future: JIT compilation can optimize hot patterns later

---

## Phase 1: Literal String Matching Only

**Goal**: Match exact literal strings with no metacharacters.

### What to Implement
```ruby
/hello/ =~ "hello world"   # => 0
/hello/ =~ "goodbye"       # => nil
"hello world" =~ /world/   # => 6
```

### Implementation Steps

1. **Parser Changes** (parser.rb, tokens.rb)
   - Parse `/pattern/` syntax (already partially done)
   - Store pattern as a string constant
   - Create `[:regexp, pattern_string, flags]` AST node

2. **Regexp Class Stub** (lib/core/regexp.rb)
   ```ruby
   class Regexp
     attr_reader :source, :options

     def initialize(pattern, options = 0)
       @source = pattern
       @options = options
     end

     def =~(string)
       # Call native matcher
       __regexp_match_literal(self, string)
     end
   end
   ```

3. **Pure Ruby Matcher** (lib/core/regexp.rb)
   ```ruby
   def =~(string)
     text = string.to_s
     pattern = @source
     plen = pattern.length
     tlen = text.length

     i = 0
     while i <= tlen - plen
       # Compare substring
       match = true
       j = 0
       while j < plen
         if text[i + j] != pattern[j]
           match = false
           break
         end
         j += 1
       end
       return i if match
       i += 1
     end
     nil
   end
   ```

4. **String#=~ Method**
   - Delegate to `Regexp#=~` with operands swapped

### Tests
```ruby
# spec/regexp_literal_spec.rb
describe "Regexp literal matching" do
  it "matches at start" do
    (/hello/ =~ "hello world").should == 0
  end

  it "matches in middle" do
    (/world/ =~ "hello world").should == 6
  end

  it "returns nil for no match" do
    (/xyz/ =~ "hello").should == nil
  end
end
```

---

## Phase 2: Basic Metacharacters

**Goal**: Support `.`, `^`, `$` metacharacters.

### What to Implement
```ruby
/.at/ =~ "cat"       # => 0 (. matches any char)
/^hello/ =~ "hello"  # => 0 (^ matches start)
/world$/ =~ "world"  # => 0 ($ matches end)
```

### Implementation Steps

1. **Regex IR (Intermediate Representation)**

   Define internal opcodes for the regex engine:
   ```ruby
   # Example IR for /^.at$/
   [:anchor_start]      # ^
   [:any_char]          # .
   [:literal, "at"]     # at
   [:anchor_end]        # $
   ```

2. **Regex Parser** (new file: regexp_parser.rb)
   ```ruby
   class RegexpParser
     def parse(pattern)
       @pos = 0
       @pattern = pattern
       @ops = []

       while @pos < @pattern.length
         case @pattern[@pos]
         when '.'
           @ops << [:any_char]
           @pos += 1
         when '^'
           @ops << [:anchor_start]
           @pos += 1
         when '$'
           @ops << [:anchor_end]
           @pos += 1
         when '\\'
           @ops << [:literal, parse_escape]
         else
           @ops << [:literal, @pattern[@pos]]
           @pos += 1
         end
       end

       @ops
     end
   end
   ```

3. **Interpreter Update**
   ```ruby
   def match(ops, text, pos)
     ops.each do |op|
       case op[0]
       when :literal
         return nil if text[pos] != op[1]
         pos += 1
       when :any_char
         return nil if pos >= text.length
         pos += 1
       when :anchor_start
         return nil if pos != 0
       when :anchor_end
         return nil if pos != text.length
       end
     end
     pos  # Return end position
   end
   ```

### Tests
```ruby
describe "Regexp metacharacters" do
  it "matches any char with ." do
    (/.at/ =~ "cat").should == 0
    (/.at/ =~ "bat").should == 0
    (/.at/ =~ "at").should == nil
  end

  it "anchors to start with ^" do
    (/^cat/ =~ "cat").should == 0
    (/^cat/ =~ "the cat").should == nil
  end

  it "anchors to end with $" do
    (/cat$/ =~ "cat").should == 0
    (/cat$/ =~ "cats").should == nil
  end
end
```

---

## Phase 3: Character Classes

**Goal**: Support `[abc]`, `[a-z]`, `[^abc]` character classes.

### What to Implement
```ruby
/[aeiou]/ =~ "hello"    # => 1 (matches 'e')
/[a-z]/ =~ "Hello"      # => 1 (matches 'e')
/[^0-9]/ =~ "abc123"    # => 0 (matches 'a', not a digit)
```

### Implementation Steps

1. **IR Extension**
   ```ruby
   [:char_class, [?a, ?e, ?i, ?o, ?u], false]  # [aeiou]
   [:char_class, [?a..?z], false]               # [a-z]
   [:char_class, [?0..?9], true]                # [^0-9] (negated)
   ```

2. **Parser Update**
   - Handle `[` ... `]` syntax
   - Parse ranges (`a-z`)
   - Handle negation (`^` as first char)
   - Handle escapes inside classes (`\]`, `\-`)

3. **Character Class Matching**
   ```ruby
   def match_char_class(char, members, negated)
     matched = members.any? do |m|
       if m.is_a?(Range)
         m.include?(char)
       else
         m == char
       end
     end
     negated ? !matched : matched
   end
   ```

4. **Predefined Classes** (shorthand)
   - `\d` = `[0-9]`
   - `\w` = `[a-zA-Z0-9_]`
   - `\s` = `[ \t\n\r\f]`
   - `\D`, `\W`, `\S` = negated versions

---

## Phase 4: Quantifiers

**Goal**: Support `*`, `+`, `?`, `{n}`, `{n,m}` quantifiers.

### What to Implement
```ruby
/ab*c/ =~ "ac"       # => 0 (zero or more b)
/ab+c/ =~ "abc"      # => 0 (one or more b)
/ab?c/ =~ "ac"       # => 0 (zero or one b)
/a{3}/ =~ "aaa"      # => 0 (exactly 3)
/a{2,4}/ =~ "aaaa"   # => 0 (2 to 4)
```

### Implementation Steps

1. **IR Extension**
   ```ruby
   [:quantifier, inner_op, min, max, greedy]
   # Examples:
   [:quantifier, [:literal, "b"], 0, :inf, true]   # b*
   [:quantifier, [:literal, "b"], 1, :inf, true]   # b+
   [:quantifier, [:literal, "b"], 0, 1, true]      # b?
   [:quantifier, [:literal, "a"], 3, 3, true]      # a{3}
   ```

2. **Greedy vs Non-Greedy**
   - Default: greedy (match as much as possible)
   - `*?`, `+?`, `??` = non-greedy (match as little as possible)

3. **Backtracking Introduction**

   This is where simple linear matching breaks down. We need backtracking:
   ```ruby
   def match_quantifier(op, text, pos, min, max, greedy)
     matches = 0
     positions = [pos]  # Stack for backtracking

     # Try to match as many as possible (greedy)
     while matches < max && (new_pos = match_single(op, text, pos))
       matches += 1
       pos = new_pos
       positions << pos
     end

     return nil if matches < min

     # Return positions for backtracking
     positions
   end
   ```

4. **Decision Point: Backtracking Strategy**

   Options:
   - **Recursive backtracking**: Simple but can stack overflow
   - **Explicit stack**: More control, can limit depth
   - **Convert to NFA**: More complex but handles all cases

---

## Phase 5: Grouping and Alternation

**Goal**: Support `(...)`, `|`, and capture groups.

### What to Implement
```ruby
/(cat|dog)/ =~ "dog"     # => 0, $1 = "dog"
/a(b+)c/ =~ "abbc"       # => 0, $1 = "bb"
/(?:foo)/ =~ "foo"       # => 0 (non-capturing)
```

### Implementation Steps

1. **IR Extension**
   ```ruby
   [:group, [...ops...], capture_index]
   [:alternation, [branch1_ops, branch2_ops, ...]]
   ```

2. **Capture Groups**
   - Track group numbers during parsing
   - Store matched substrings in `$1`, `$2`, etc.
   - Implement `MatchData` class

3. **MatchData Class**
   ```ruby
   class MatchData
     def initialize(string, captures)
       @string = string
       @captures = captures
     end

     def [](n)
       @captures[n]
     end

     def to_a
       @captures
     end
   end
   ```

4. **Alternation Matching**
   - Try each branch in order
   - First successful match wins
   - Backtrack if later matching fails

---

## Phase 6: Advanced - NFA/DFA Compilation

**Goal**: Compile regex patterns to efficient finite automata.

### Theory Background

1. **NFA (Non-deterministic Finite Automaton)**
   - Direct translation from regex
   - Multiple possible states at once
   - Uses Thompson's construction algorithm
   - Handles all regex features including backreferences

2. **DFA (Deterministic Finite Automaton)**
   - One state at a time
   - Faster matching (O(n) guaranteed)
   - Can be exponentially larger than NFA
   - Cannot handle backreferences

### Implementation Approach

1. **Thompson's Construction** (Regex → NFA)
   ```ruby
   class NFABuilder
     def build_literal(char)
       start = State.new
       accept = State.new
       start.add_transition(char, accept)
       NFA.new(start, accept)
     end

     def build_concat(nfa1, nfa2)
       nfa1.accept.add_epsilon(nfa2.start)
       NFA.new(nfa1.start, nfa2.accept)
     end

     def build_union(nfa1, nfa2)
       start = State.new
       accept = State.new
       start.add_epsilon(nfa1.start)
       start.add_epsilon(nfa2.start)
       nfa1.accept.add_epsilon(accept)
       nfa2.accept.add_epsilon(accept)
       NFA.new(start, accept)
     end

     def build_star(nfa)
       start = State.new
       accept = State.new
       start.add_epsilon(nfa.start)
       start.add_epsilon(accept)
       nfa.accept.add_epsilon(nfa.start)
       nfa.accept.add_epsilon(accept)
       NFA.new(start, accept)
     end
   end
   ```

2. **Subset Construction** (NFA → DFA)
   ```ruby
   class DFABuilder
     def convert(nfa)
       # Each DFA state = set of NFA states
       dfa_start = epsilon_closure([nfa.start])
       worklist = [dfa_start]
       dfa_states = {dfa_start => DFAState.new}

       while state_set = worklist.shift
         dfa_state = dfa_states[state_set]

         each_input_symbol do |sym|
           next_set = epsilon_closure(move(state_set, sym))
           next unless next_set.any?

           unless dfa_states[next_set]
             dfa_states[next_set] = DFAState.new
             worklist << next_set
           end

           dfa_state.add_transition(sym, dfa_states[next_set])
         end
       end

       DFA.new(dfa_states[dfa_start])
     end
   end
   ```

3. **Code Generation** (DFA → S-Expression/Ruby Code)

   For AOT compilation, generate s-expressions or inline Ruby for DFA.
   Example DFA state machine for /ab+c/ as s-expressions:
   ```ruby
   # DFA compiled to inline matching code
   # Generated from DFA transition tables
   [:do,
     [:assign, :state, 0],
     [:assign, :pos, 0],
     [:while, [:lt, :pos, [:callm, :text, :length]],
       [:do,
         [:assign, :c, [:index, :text, :pos]],
         [:case, :state,
           [0, [:if, [:eq, :c, "a"],
                 [:do, [:assign, :state, 1], [:assign, :pos, [:+, :pos, 1]]],
                 [:return, nil]]],
           [1, [:if, [:eq, :c, "b"],
                 [:do, [:assign, :state, 2], [:assign, :pos, [:+, :pos, 1]]],
                 [:return, nil]]],
           [2, [:if, [:eq, :c, "b"],
                 [:assign, :pos, [:+, :pos, 1]],  # stay in state 2
                 [:if, [:eq, :c, "c"],
                   [:return, :match_start],
                   [:return, nil]]]]]]],
     :nil]
   ```

   Or as pure Ruby for runtime interpretation:
   ```ruby
   def match_dfa(text)
     transitions = {
       0 => {"a" => 1},
       1 => {"b" => 2},
       2 => {"b" => 2, "c" => :accept}
     }
     state = 0
     text.each_char.with_index do |c, pos|
       next_state = transitions[state][c]
       return nil unless next_state
       return pos - pattern.length + 1 if next_state == :accept
       state = next_state
     end
     nil
   end
   ```

---

## Phase 7: Ruby-Specific Features

### Additional Features to Implement

1. **Flags/Modifiers**
   - `i` - case insensitive
   - `m` - multiline (`.` matches newline)
   - `x` - extended (ignore whitespace, allow comments)

2. **Special Constructs**
   - `\b`, `\B` - word boundaries
   - `\A`, `\z`, `\Z` - absolute anchors
   - `(?=...)`, `(?!...)` - lookahead
   - `(?<=...)`, `(?<!...)` - lookbehind

3. **Named Groups**
   ```ruby
   /(?<year>\d{4})-(?<month>\d{2})/ =~ "2024-01"
   # $~[:year] => "2024"
   ```

4. **Backreferences**
   ```ruby
   /(.)\1/ =~ "aa"  # Match repeated char
   ```

   Note: Backreferences require NFA simulation, cannot use pure DFA.

5. **String Methods**
   - `String#match`, `String#scan`, `String#gsub`, `String#split`
   - Each needs regex support

---

## Recommended Implementation Order

| Phase | Effort | Value | Priority |
|-------|--------|-------|----------|
| 1. Literal matching | Low | High | P0 |
| 2. Basic metacharacters | Low | High | P0 |
| 3. Character classes | Medium | High | P1 |
| 4. Quantifiers | Medium | High | P1 |
| 5. Groups/Alternation | Medium | Medium | P2 |
| 6. NFA/DFA compilation | High | Medium | P3 |
| 7. Ruby-specific | High | Low | P4 |

### Milestones

**Milestone 1: Basic Regex** (Phases 1-2)
- Literal matching with `.`, `^`, `$`
- Enough for simple pattern matching
- ~200 lines of code

**Milestone 2: Practical Regex** (Phases 3-4)
- Character classes and quantifiers
- Handles most common patterns
- ~500 additional lines

**Milestone 3: Full Regex** (Phases 5-6)
- Groups, alternation, captures
- DFA compilation for performance
- ~1000 additional lines

**Milestone 4: Ruby Compatible** (Phase 7)
- All Ruby regex features
- Full rubyspec compatibility
- ~500 additional lines

---

## File Organization

```
lib/core/regexp.rb          # Regexp class
lib/core/matchdata.rb       # MatchData class
regexp_parser.rb            # Parse regex patterns to IR
regexp_compiler.rb          # Compile IR to native code (optional)
regexp_interpreter.rb       # Runtime matcher (fallback)
```

## References

- [Regular Expression Matching Can Be Simple And Fast](https://swtch.com/~rsc/regexp/regexp1.html) - Russ Cox
- [Thompson's Construction Algorithm](https://en.wikipedia.org/wiki/Thompson%27s_construction)
- [Ruby Regexp Documentation](https://ruby-doc.org/core/Regexp.html)
- Dragon Book, Chapter 3 (Lexical Analysis)
- [Building a Regex Engine](https://jasonhpriestley.com/regex) - Jason Priestley
  - Progressive implementation from NFA primitives (zero, one, eps, lit, seq, alt, star)
  - Shows elegant layering: primitives → operators → parser → matcher
- [Regex to DFA Compilation](https://jasonhpriestley.com/regex-dfa) - Jason Priestley
  - DFA compilation for performance (linear-time matching)
  - State numbering and transition table generation
  - Path to native code generation via intermediate representation
