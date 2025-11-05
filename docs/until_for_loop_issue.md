# Until and For Loop Support Issue

## Problem

Commits 41ae660 "Add until loop support" and 3a3704c "Add for loop parsing support with destructuring" were not re-applied because they caused merge conflicts with the working baseline.

These features are needed for various RubySpec tests but couldn't be cherry-picked cleanly.

## Until Loop (41ae660)

### What It Does

Implements `until` loops, which are the inverse of `while` loops:
```ruby
until condition
  # code runs while condition is FALSE
end
```

### Implementation Added

**parser.rb:**
- `parse_until` method to parse until...do...end constructs

**compile_control.rb:**
- `compile_until` method to generate loop code
- `compile_jmp_on_true` helper to jump when condition is truthy

**compiler.rb:**
- Added `:until` to case statement in `compile_exp`

### Why It's Needed

RubySpec fixtures use until loops:
- `next_spec.rb` - Tests for `next` keyword
- Various control flow specs
- Iterator tests

Example from specs:
```ruby
i = 0
until i > 5
  i += 1
  next if i == 3
end
```

### Why It Couldn't Be Applied

Cherry-pick failed with conflicts in `parser.rb`:
```
Auto-merging parser.rb
CONFLICT (content): Merge conflict in parser.rb
```

The conflicts are because:
1. Parser has diverged significantly from f1f871f
2. Keyword handling code has changed
3. Context-sensitive keyword infrastructure was added in intervening commits

## For Loop (3a3704c)

### What It Does

Implements `for` loops with destructuring support:
```ruby
for x in array
  # code
end

for a, b in array_of_pairs
  # destructuring assignment
end
```

### Implementation Added

**parser.rb:**
- `parse_for` method to parse for...in...end constructs
- Support for destructuring in loop variables

**Keywords updated:**
```ruby
Keywords = Set[
  ..., :for, ...
]
```

### Why It's Needed

RubySpec tests use for loops:
- `for_spec.rb` - Dedicated for loop tests
- `destructuring_spec.rb` - Destructuring in for loops
- Various iterator specs

Example from specs:
```ruby
for i in [1, 2, 3]
  sum += i
end

for key, value in hash
  # process pairs
end
```

### Why It Couldn't Be Applied

Would cause the same merge conflicts as until loop since both modify parser.rb in similar ways.

## Next Steps to Fix

### Option 1: Manual Re-implementation

Since the code diverged, manually reimplement the features:

1. **Add keywords to tokens.rb:**
   ```ruby
   Keywords = Set[
     ..., :while, :until, :for
   ]
   ```

2. **Add parsing methods to parser.rb:**
   - Study the original `parse_until` and `parse_for` implementations
   - Adapt them to current parser structure
   - Handle keyword context sensitivity properly

3. **Add compilation methods:**
   - `compile_until` can reuse `compile_while` logic with inverted condition
   - `compile_for` can transform to iterator-based loop

4. **Test incrementally:**
   ```bash
   # After each addition:
   make compiler
   make selftest
   make selftest-c
   ```

### Option 2: Three-Way Merge

Manually merge the changes:

1. **Extract the diff:**
   ```bash
   git show 41ae660 > /tmp/until.patch
   git show 3a3704c > /tmp/for.patch
   ```

2. **Study what changed:**
   - Identify all additions/modifications
   - Understand interaction with current code

3. **Apply manually:**
   - Add each piece carefully
   - Resolve conflicts as they arise
   - Test after each logical chunk

### Option 3: Rebase Approach

Create a branch from f1f871f and rebase:

```bash
git checkout -b feature/control-loops f1f871f
git cherry-pick 41ae660  # until
git cherry-pick 3a3704c  # for
# These should apply cleanly

# Then cherry-pick our fixes:
git cherry-pick 104f818  # Binding class
git cherry-pick 4949a84  # Operators

# Test:
make compiler && make selftest && make selftest-c
```

If this works, use it as the new master.

## Implementation Details

### Until Loop

The implementation is straightforward:

```ruby
def compile_until(scope, cond, body)
  @e.loop do |br,l|
    var = compile_eval_arg(scope, cond)
    compile_jmp_on_true(scope, var, br)  # Jump on true (opposite of while)
    compile_exp(ControlScope.new(scope, br,l), body)
  end
  compile_eval_arg(scope, :nil)
  return Value.new([:subexpr])
end

def compile_jmp_on_true(scope, r, target)
  # Jump if value is NOT nil and NOT false
  if r && r.type == :object
    @e.save_result(r)
    @e.evict_all
    skip = @e.get_local
    @e.cmpl(@e.result_value, "nil")
    @e.je(skip)
    @e.cmpl(@e.result_value, "false")
    @e.je(skip)
    @e.jmp(target)
    @e.local(skip)
  else
    @e.evict_all
    skip = @e.get_local
    @e.jmp_on_false(skip, r)
    @e.jmp(target)
    @e.local(skip)
  end
end
```

This is the inverse of `compile_jmp_on_false` and can be adapted to current codebase.

### For Loop

For loops can be transformed to iterators:

```ruby
# for x in array
#   body
# end

# Transforms to:
# array.each do |x|
#   body
# end
```

This avoids implementing new compilation logic and reuses existing iterator support.

## Testing Strategy

1. **Create minimal test files:**
   ```ruby
   # test_until.rb
   i = 0
   until i > 5
     puts i
     i += 1
   end
   ```

   ```ruby
   # test_for.rb
   for x in [1,2,3]
     puts x
   end
   ```

2. **Test compilation:**
   ```bash
   ./compile test_until.rb -I. && ./out/test_until
   ./compile test_for.rb -I. && ./out/test_for
   ```

3. **Test self-compilation:**
   After features work, ensure they don't break selftest-c

4. **Run affected specs:**
   ```bash
   ./run_rubyspec spec/ruby/language/until_spec.rb
   ./run_rubyspec spec/ruby/language/for_spec.rb
   ```

## Files To Modify

- `tokens.rb` - Add `:until` and `:for` to Keywords
- `parser.rb` - Add `parse_until` and `parse_for` methods
- `compile_control.rb` - Add `compile_until` and `compile_for` methods
- `compiler.rb` - Add cases for `:until` and `:for` in `compile_exp`

## Priority

Medium - These features are needed for specs but have workarounds:
- Until loops can be written as while loops with inverted conditions
- For loops can be written as `.each` iterators

However, implementing them properly will:
1. Unblock more RubySpec tests
2. Make spec fixture code work as-is
3. Improve Ruby compatibility

## Specs Affected

From commit messages:
- `next_spec.rb` - Uses until loops
- `for_spec.rb` - Dedicated for loop tests
- Various control flow and iterator specs

Estimated impact:
- Until: ~5-10 specs
- For: ~10-15 specs
