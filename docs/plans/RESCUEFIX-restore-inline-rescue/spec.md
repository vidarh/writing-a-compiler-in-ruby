RESCUEFIX
Created: 2026-03-02

# Restore Inline Rescue Modifier in emitter.rb

[SELFHOST] Test whether the inline rescue modifier (`expr rescue default`) works in the
self-hosted compiler, and if so, restore the original `@allocator.lock_reg(maybe_reg) rescue nil`
one-liner in [emitter.rb](../../emitter.rb), removing the `respond_to?(:to_sym)` workaround
that was added under the false assumption that exceptions were unsupported.

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

## Prior Plans

- **[BUGAUDIT](../archived/BUGAUDIT-validate-bug-workarounds/spec.md)** (Status: IMPLEMENTED):
  Catalogued all `@bug` markers including marker 21 (`emitter.rb:399`, inline rescue). The first
  execution marked it **OUT OF SCOPE** with the comment "exception handling not implemented."
  The user corrected this: *"Exceptions* are *supported. Several of your updates are incorrectly
  making assumptions that are outdated without verifying if they are true."* The plan was
  re-opened for a second execution (2026-02-14 14:38), but the final [log.md](../archived/BUGAUDIT-validate-bug-workarounds/log.md)
  still shows marker 21 as "OUT OF SCOPE." No spec for inline rescue was created. No workaround
  was removed. **This plan picks up exactly where BUGAUDIT left off.**

  **What is different**: BUGAUDIT was diagnostic — it audited all 25 markers and explicitly
  scoped out fixing them. This plan is a targeted fix for the single remaining marker that was
  incorrectly excluded. It tests the *inline rescue modifier syntax* specifically (not block rescue,
  which is already known to work), and removes the workaround if the test passes.

## Root Cause

[emitter.rb:398-420](../../emitter.rb) contains `with_register_for`, which handles conditional
register locking. The original Ruby idiom is:

```ruby
c = @allocator.lock_reg(maybe_reg) rescue nil
```

This uses the **inline rescue modifier** — a trailing `rescue` after an expression that returns a
default value when an exception is raised. `lock_reg` raises when `maybe_reg` is not a lockable
register symbol (e.g., when it's an integer memory operand), and the `rescue nil` makes the call
return `nil` gracefully in that case.

The current workaround substitutes a type-check guard:

```ruby
c = nil
if maybe_reg.respond_to?(:to_sym)
  c = @allocator.lock_reg(maybe_reg)
end
```

This was added because "lack of support for exceptions" was assumed. However:

1. The assumption is **false** — block rescue (`begin...rescue...end` and do-block rescue) is
   implemented and tested (see [spec/do_block_rescue_spec.rb](../../spec/do_block_rescue_spec.rb)).

2. The workaround has a **semantic difference**: if `maybe_reg` responds to `:to_sym` but
   `lock_reg` raises for some other reason, the workaround propagates the exception while the
   original silently returns `nil`. This is a latent correctness risk.

3. The inline rescue modifier (`expr rescue default`) is a distinct parser feature from block
   rescue. No existing spec tests this specific syntax in the self-hosted compiler context. The
   BUGAUDIT plan included a step (Execution Step 9) to create `spec/bug_inline_rescue_spec.rb`
   — that step was never carried out.

**Why the root cause was missed**: BUGAUDIT marker 21 was designated out of scope early in the
first execution. The user's correction came after the first execution completed. The second
execution (BUGAUDIT retry) focused on re-verifying already-tested markers and updating the
log summary, but did not re-open the marker 21 investigation.

## Infrastructure Cost

Zero. This adds one spec file to `spec/` and modifies three lines in [emitter.rb](../../emitter.rb).
No new files beyond the spec, no build system changes, no tooling changes. Validation uses
existing `make selftest`, `make selftest-c`, and `./run_rubyspec spec/bug_inline_rescue_spec.rb`.

## Scope

**In scope:**

1. Create `spec/bug_inline_rescue_spec.rb` testing:
   - Basic inline rescue: `raise_method rescue nil` returns nil when raise_method raises
   - Inline rescue with non-nil default: `raise_method rescue 42` returns 42
   - Inline rescue on non-raising expression: `normal_method rescue nil` returns the method result
   - Assignment context: `x = raise_method rescue nil` assigns nil to x
   - The `lock_reg`-equivalent pattern: a method that raises when its argument is invalid,
     called with `rescue nil` — mirrors the exact emitter.rb usage

2. Run the spec against the self-hosted compiler to determine if inline rescue works

3. **If inline rescue works**: restore the original code in [emitter.rb:399-406](../../emitter.rb):
   ```ruby
   def with_register_for(maybe_reg, &block)
     c = @allocator.lock_reg(maybe_reg) rescue nil
     ...
   end
   ```
   Remove the `@FIXME @bug` comment and the `if maybe_reg.respond_to?(:to_sym)` guard.

4. **If inline rescue fails**: document the specific failure mode in the spec comments and in
   [docs/KNOWN_ISSUES.md](../../docs/KNOWN_ISSUES.md), cross-reference the spec file in the
   `@bug` comment in emitter.rb, and update the BUGAUDIT log to reflect verified status.

5. Validate with `make selftest` and `make selftest-c` if workaround was removed.

**Out of scope:**
- Block rescue (`begin...rescue...end`) — already known to work
- Other `@bug` markers in emitter.rb (lines 409, 417: yield in nested blocks — those are
  Category 1, covered by the [YIELDFIX](../YIELDFIX-fix-yield-in-nested-blocks/spec.md) plan)
- Exception handling improvements beyond inline rescue
- Implementing the `rescue =>` binding form (tested separately in
  [spec/rescue_safe_navigation_spec.rb](../../spec/rescue_safe_navigation_spec.rb))

## Expected Payoff

**If inline rescue works (likely):**
- One `@bug` workaround removed from [emitter.rb](../../emitter.rb)
- The semantic correctness risk eliminated (workaround misses `lock_reg` raising for unexpected reasons)
- Marker 21 moves from "OUT OF SCOPE" to "STALE — REMOVED" in the BUGAUDIT inventory
- Direct advancement of [SELFHOST](../../goals/SELFHOST-clean-bootstrap.md): one fewer workaround
  in the compiler's own source

**If inline rescue does not work:**
- Bug documented with a spec that reproduces it
- BUGAUDIT log updated with verified status instead of wrong "out of scope" label
- Baseline for a future fix (understanding what specifically fails about the modifier form)

**Either way:**
- The long-standing incorrect "OUT OF SCOPE" label on marker 21 is resolved
- The BUGAUDIT inventory is accurate and complete for the first time

## Proposed Approach

### Step 1: Write the spec

Create `spec/bug_inline_rescue_spec.rb`:

```ruby
require_relative '../rubyspec/spec_helper'

# Tests inline rescue modifier: expr rescue default_value
# Related @bug marker: emitter.rb:399
# BUGAUDIT marker 21 (Category 8: Miscellaneous)

class InlineRescueTest
  def raises_always
    raise "error"
  end

  def raises_on_bad_arg(x)
    raise ArgumentError, "bad arg" if x == :bad
    x
  end

  def does_not_raise
    42
  end
end

describe "Inline rescue modifier" do
  before do
    @obj = InlineRescueTest.new
  end

  it "returns nil when method raises" do
    result = @obj.raises_always rescue nil
    result.should == nil
  end

  it "returns default when method raises" do
    result = @obj.raises_always rescue 99
    result.should == 99
  end

  it "returns method result when no exception" do
    result = @obj.does_not_raise rescue nil
    result.should == 42
  end

  it "works in assignment context" do
    x = @obj.raises_always rescue nil
    x.should == nil
  end

  it "works with conditional-raise method (bad arg)" do
    result = @obj.raises_on_bad_arg(:bad) rescue nil
    result.should == nil
  end

  it "works with conditional-raise method (good arg)" do
    result = @obj.raises_on_bad_arg(:good) rescue nil
    result.should == :good
  end
end
```

### Step 2: Run the spec

```
./run_rubyspec spec/bug_inline_rescue_spec.rb
```

Record which tests pass and which fail (if any).

### Step 3a: If all tests pass — remove the workaround

In [emitter.rb:398-420](../../emitter.rb):

```ruby
def with_register_for(maybe_reg, &block)
  c = @allocator.lock_reg(maybe_reg) rescue nil

  if c
    comment("Locked register #{c.reg}")
    block.call(c.reg) # FIXME: @bug - yield does not work here.
    comment("Unlocked register #{c.reg}")
    c.locked = false
    return block.call(c.reg)
  end
  with_register do |r|
    emit(:movl, maybe_reg, r)
    block.call(r) # FIXME: @bug - yield does not work here.
  end
end
```

Wait — re-reading the original code, `block.call(c.reg)` appears **twice** in the `if c` branch
(lines 410 and 412). The first is the actual call; the second is inside a `return`. These are
two separate `@bug` comments (yield-related, Category 1, covered by YIELDFIX). The inline rescue
workaround is ONLY lines 399-405 — the guard for `lock_reg`. The correct restoration is:

```ruby
def with_register_for(maybe_reg, &block)
  c = @allocator.lock_reg(maybe_reg) rescue nil    # restored from @bug workaround

  if c
    comment("Locked register #{c.reg}")
    r = block.call(c.reg)  # FIXME: @bug - yield does not work here.
    comment("Unlocked register #{c.reg}")
    c.locked = false
    return r
  end
  with_register do |r|
    emit(:movl, maybe_reg, r)
    block.call(r)  # FIXME: @bug - yield does not work here.
  end
end
```

Then run `make selftest && make selftest-c` to confirm no regressions.

### Step 3b: If tests fail — document and update records

- Add a comment to the relevant failing test(s) explaining what specifically failed
- Add an entry to [docs/KNOWN_ISSUES.md](../../docs/KNOWN_ISSUES.md) referencing the spec
- Update the `@FIXME @bug` comment in emitter.rb:399 to reference the spec file:
  ```ruby
  # @FIXME @bug - inline rescue modifier does not work (see spec/bug_inline_rescue_spec.rb)
  # @bug: lock_reg raises when maybe_reg is not a register symbol; workaround:
  c = nil
  if maybe_reg.respond_to?(:to_sym)
    c = @allocator.lock_reg(maybe_reg)
  end
  ```

## Acceptance Criteria

- [ ] `spec/bug_inline_rescue_spec.rb` exists and uses correct mspec format
  (`require_relative '../rubyspec/spec_helper'`, `describe/it/.should` structure)

- [ ] `./run_rubyspec spec/bug_inline_rescue_spec.rb` has been run and results recorded

- **One of the following must be true (mutually exclusive):**

  - [ ] **Path A**: All 6 tests in `spec/bug_inline_rescue_spec.rb` pass, AND
    [emitter.rb:399-405](../../emitter.rb) has been restored to
    `c = @allocator.lock_reg(maybe_reg) rescue nil`, AND the `@FIXME @bug` comment is removed,
    AND `make selftest` and `make selftest-c` both pass.

  - [ ] **Path B**: One or more tests fail, AND a [docs/KNOWN_ISSUES.md](../../docs/KNOWN_ISSUES.md)
    entry documents the specific failure mode, AND the `@FIXME @bug` comment in emitter.rb
    references `spec/bug_inline_rescue_spec.rb`.

- [ ] BUGAUDIT [log.md](../archived/BUGAUDIT-validate-bug-workarounds/log.md) marker 21 entry
  updated from "OUT OF SCOPE" to either "STALE — REMOVED" (Path A) or "CONFIRMED" (Path B)

## Open Questions

- Does the inline rescue modifier form appear in the compiler's parser at all? If the parser
  doesn't recognize `expr rescue default` as a valid expression form, the spec will fail with a
  parse error rather than a runtime error — which would require a parser-level fix rather than
  a simple workaround removal. Check [parser.rb](../../parser.rb) for `rescue_mod` or
  equivalent tokens before running the spec.

- The `if maybe_reg.respond_to?(:to_sym)` check is actually slightly **weaker** than the
  original `rescue nil` — it allows calling `lock_reg` for any object that responds to `:to_sym`
  (Symbols and Strings both do), while the original would call `lock_reg` regardless and catch
  any failure. If `lock_reg` can raise for a `:to_sym`-responding argument, the workaround may
  have introduced a latent bug. The restored version with `rescue nil` would be strictly more
  robust.

---
*Status: PROPOSAL - Awaiting approval*
