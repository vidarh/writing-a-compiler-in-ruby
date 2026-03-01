BGFIX
Created: 2026-03-01

# Fix `block_given?` in Nested Block Contexts

[SELFHOST] Fix `rewrite_env_vars` in [transform.rb](../../transform.rb) so that `block_given?`
inside a nested block (lambda/do-block) correctly checks whether the *outer method* was called
with a block — matching Ruby semantics — and remove the confirmed `@bug` workaround from
[compile_arithmetic.rb:115](../../compile_arithmetic.rb).

## Goal Reference

[SELFHOST](../../goals/SELFHOST-clean-bootstrap.md)

Also advances [COMPLANG](../../goals/COMPLANG-compiler-advancement.md): any compiled program or
rubyspec test that uses `block_given?` inside an iterator block (a common Ruby idiom) currently
crashes. After this fix, such programs run correctly.

## Prior Plans

- **[BUGAUDIT](../archived/BUGAUDIT-validate-bug-workarounds/spec.md)** (Status: IMPLEMENTED):
  Audited all 25 `@bug` markers. Confirmed Cat 4 (block_given? in nested blocks, marker 15,
  [compile_arithmetic.rb:115](../../compile_arithmetic.rb)) as reproducing with segfault in nested
  block context. Created [spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb)
  (2 runnable tests pass; 3 commented-out tests crash). BUGAUDIT was diagnostic — it documented
  the bug but explicitly excluded fixing it. This plan targets the confirmed Cat 4 bug.

- **[YIELDFIX](../YIELDFIX-fix-yield-in-nested-blocks/spec.md)** (Status: PROPOSAL): Fixes the
  related but distinct bug where `yield` inside a nested block crashes. YIELDFIX addresses the
  `[:call, :yield]` → `[:callm, :__closure__, :call, args]` rewrite. BGFIX addresses the
  `[:call, :"block_given?"]` expansion — a different AST node and a different expansion rule,
  requiring an independent fix. These plans can be executed in either order with no dependency.

No prior plan has ever attempted to fix this specific bug.

## Root Cause

`block_given?` is compiled by two different mechanisms at different pipeline stages:

**Stage 1 — Transform (rewrite_env_vars):**
When a method contains nested blocks (lambdas/do-blocks), [transform.rb](../../transform.rb)
processes the nested block's body through `rewrite_env_vars`. This function rewrites captured
variables to `[:index, :__env__, N]` closure-environment accesses. The outer method's block
pointer (`__closure__`) is always captured into env slot N_CLOSURE (line 863:
`env << :__closure__`), so `__closure__` inside the nested block body is replaced with
`[:index, :__env__, N_CLOSURE]`.

**Stage 2 — Compile (compiler.rb:159):**
```ruby
if a == :"block_given?"
  return compile_exp(scope, [:if, [:ne, :__closure__, 0], :true, :false])
end
```
This expansion happens at compile time, AFTER the transform phase. It generates code that
compares `__closure__` against 0.

**The bug:** Inside a nested block body, `block_given?` appears as `[:call, :"block_given?"]`
in the AST. `rewrite_env_vars` has no handling for this node, so it passes through unmodified.
At compile time (Stage 2), `compiler.rb:159` expands it to `[:ne, :__closure__, 0]` — but at
compile time inside the nested block's scope, `__closure__` refers to the *nested block's own*
closure parameter (which is null, since do-blocks are not called with their own block argument).
The comparison always returns false, and depending on optimizer state, may segfault.

**Contrast with `yield`:** The yield expansion is handled at Stage 1 (inside `rewrite_env_vars`,
lines 759–766), not at Stage 2. After expansion to `[:callm, :__closure__, :call, args]`, the
general env-var rewriting at lines 768–801 replaces `__closure__` with `[:index, :__env__, N]`.
This is why yield works (when YIELDFIX is applied) but `block_given?` does not.

**Evidence:** [docs/plans/archived/BUGAUDIT-validate-bug-workarounds/log.md](../archived/BUGAUDIT-validate-bug-workarounds/log.md),
marker 15: "compile_arithmetic.rb:115 — Cat 4: block_given? nested — CONFIRMED — Segfault / nil
return in nested block." [spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb)
has 3 test cases commented out as "CONFIRMED BUG: segfault".

```mermaid
flowchart TD
    A["Parser\n[:call, :\"block_given?\"]"] --> B["rewrite_env_vars\n(no handler → passes through)"]
    B --> C["compiler.rb:159\nExpands to [:ne, :__closure__, 0]\nBUG: __closure__ = nested block's own,\nnot outer method's block"]
    C --> D["Runtime: always false / segfault"]

    A2["Parser\n[:call, :\"block_given?\"]"] --> B2["FIXED rewrite_env_vars\nExpand to [:ne, :__closure__, 0]\nThen env-var rewrite:\n__closure__ → [:index, :__env__, N]"]
    B2 --> C2["Result: [:ne, [:index, :__env__, N], 0]\ncompiler.rb:159 NOT triggered"]
    C2 --> D2["Runtime: correctly tests outer closure"]

    style D fill:#f88
    style D2 fill:#8f8
```

## Infrastructure Cost

Zero. The fix is a single conditional block (~5 lines) added to `rewrite_env_vars` in
[transform.rb](../../transform.rb), between the yield expansion (line 766) and the
`e.each_with_index` loop (line 768). No new files, no build system changes, no new dependencies.
Validation uses [spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb)
(existing file), `make selftest`, and `make selftest-c`.

## Scope

**In scope:**

1. **Add `block_given?` expansion to `rewrite_env_vars`** in [transform.rb](../../transform.rb),
   between lines 766 and 768 (after yield handling, before `e.each_with_index`):

   ```ruby
   # block_given? inside nested blocks must check the outer method's __closure__
   # Expand here so __closure__ gets rewritten to [:index, :__env__, N] below.
   if e.is_a?(Array) && e[0] == :call && e[1] == :"block_given?"
     seen = true
     e[0] = :ne
     e[1] = :__closure__
     e[2] = 0
   end
   ```

   After this expansion, the `e.each_with_index` loop at line 768 processes `e[1] = :__closure__`.
   Since `__closure__` is always in `aenv` (line 863 guarantees this), it gets replaced with
   `[:index, :__env__, N_CLOSURE]`. Final result: `[:ne, [:index, :__env__, N_CLOSURE], 0]`.

2. **Validate with `make selftest`** — regression gate for MRI-compiled compiler.

3. **Validate with `make selftest-c`** — regression gate for self-hosted compiler.

4. **Uncomment the 3 crashing test cases** in
   [spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb):
   - `check_bg_nested`: `block_given?` inside one nested do-block
   - `check_bg_doubly_nested`: `block_given?` inside doubly-nested do-blocks
   - `check_bg_lambda`: `block_given?` inside a lambda

   Run `./run_rubyspec spec/bug_block_given_nested_spec.rb` to confirm all 5 tests pass.

5. **Remove the `@bug` workaround** from [compile_arithmetic.rb:115–118](../../compile_arithmetic.rb):
   - Remove `bg = block_given?` (line 118)
   - Remove the `@bug` comment (lines 115–117)
   - Replace `if bg` (line 129) with `if block_given?`
   - Run `make selftest` and `make selftest-c` to confirm no regressions.

6. **Update the `@bug` comment** at [compile_arithmetic.rb:115](../../compile_arithmetic.rb) to
   remove it entirely (or mark as FIXED with date if any reference is needed).

**Out of scope:**

- Fixing yield in nested blocks — that is YIELDFIX (separate plan, independent).
- Fixing break register corruption (Cat 7) — separate bug.
- Fixing variable-name collision (Cat 2) — covered by ENVFIX.
- Fixing ternary precedence (Cat 3) — covered by TERNPREC.
- Adding the `block.call` → `yield` cleanup in `compile_arithmetic.rb:130` — that requires YIELDFIX to land first. The BGFIX workaround removal only changes `bg = block_given?` → direct `block_given?`; `block.call` stays until YIELDFIX removes it.

## Expected Payoff

**Direct (SELFHOST):**
- [spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb) changes from
  2 passing + 3 commented-out (crashers) to 5 passing + 0 commented-out.
- 1 `@bug` workaround removed from [compile_arithmetic.rb](../../compile_arithmetic.rb) (marker 15
  from BUGAUDIT). Confirmed @bug marker count drops from ~18 to ~17.
- Compiler source becomes more idiomatic: `if block_given?` used directly instead of pre-capture.

**Indirect (COMPLANG):**
- All compiled programs can now use `block_given?` inside iterators — a common Ruby pattern:
  ```ruby
  def each_if_block
    [1,2,3].each do |x|
      yield x if block_given?
    end
  end
  ```
- rubyspec tests that check `block_given?` inside iterators now run correctly instead of crashing.
- Enumerable methods implemented in `lib/core/` that guard with `block_given?` inside iterators
  become safe to call without pre-capturing the guard.

## Proposed Approach

**Step 1: Reproduce and baseline**

Run `./run_rubyspec spec/bug_block_given_nested_spec.rb` to confirm: 2 tests run (pass), 3
commented out (would crash). Document exact output.

**Step 2: Add the transform expansion**

In [transform.rb](../../transform.rb), locate the yield expansion block (around lines 756–766):

```ruby
# We need to expand "yield" before we rewrite.
# yield becomes __closure__.call(args...)
if e.is_a?(Array) && e[0] == :call && e[1] == :yield
  seen = true
  args = e[2] || []
  e[0] = :callm
  e[1] = :__closure__
  e[2] = :call
  e[3] = args.is_a?(Array) ? args : [args]
end
```

Immediately after this block (before line 768's `e.each_with_index`), add:

```ruby
# block_given? inside nested blocks: expand here so __closure__ gets rewritten
# to [:index, :__env__, N] by the env-var rewriting loop below.
if e.is_a?(Array) && e[0] == :call && e[1] == :"block_given?"
  seen = true
  e[0] = :ne
  e[1] = :__closure__
  e[2] = 0
end
```

This mirrors the yield expansion pattern. After this runs, `e.each_with_index` at line 768 sees
`e[1] = :__closure__`, finds it in `env`, and replaces it with `[:index, :__env__, N_CLOSURE]`.
Final AST: `[:ne, [:index, :__env__, N_CLOSURE], 0]`.

At compile time, `compiler.rb:159` is no longer triggered for these nodes (since `e[0]` is now
`:ne`, not `:call`). The compiler compiles `[:ne, x, 0]` as a normal comparison.

**Step 3: Run selftest**

`make selftest` — this compiles the compiler source under MRI and runs the self-test. If it fails:
- The expansion may have incorrectly matched a call unrelated to `block_given?`
- Check that `e[1] == :"block_given?"` is exact (not `:block_given?`)
- Revert and re-examine using git stash (per CLAUDE.md rules)

**Step 4: Run selftest-c**

`make selftest-c` — validates self-hosting. If selftest passes but selftest-c fails, the
self-hosted compiler is affected. Investigate whether the expansion produces an AST that the
self-hosted compiler handles incorrectly.

**Step 5: Uncomment test cases**

If both selftests pass, uncomment the 3 crashing test cases in
[spec/bug_block_given_nested_spec.rb](../../spec/bug_block_given_nested_spec.rb):

```ruby
def check_bg_nested(&block)
  result = nil
  [1].each do |x|
    result = block_given?
  end
  result
end

def check_bg_doubly_nested(&block)
  result = nil
  [1].each do |x|
    [2].each do |y|
      result = block_given?
    end
  end
  result
end

def check_bg_lambda(&block)
  f = lambda { block_given? }
  f.call
end
```

And the corresponding `it` blocks in the describe section. Run:
`./run_rubyspec spec/bug_block_given_nested_spec.rb`

Expected: all 5 tests pass. If a specific case still crashes (e.g., doubly-nested or lambda),
investigate separately and leave that case commented with an updated note. At minimum the
single-nesting case (`check_bg_nested`) must pass.

**Step 6: Remove the compile_arithmetic.rb workaround**

In [compile_arithmetic.rb](../../compile_arithmetic.rb), change:

```ruby
# @bug: block_given? inside nested blocks causes segfault
# (confirmed 2026-02-14). Workaround: capture to local before
# entering nested block. See spec/bug_block_given_nested_spec.rb
bg = block_given?
@e.with_register(:edx) do |dividend|
  @e.with_register do |divisor|
    ...
    if bg
      block.call
    end
  end
end
```

To:

```ruby
@e.with_register(:edx) do |dividend|
  @e.with_register do |divisor|
    ...
    if block_given?
      block.call
    end
  end
end
```

(Note: `block.call` stays; it is not changed to `yield` since that requires YIELDFIX to land
first — the `yield` in a doubly-nested block would still crash without YIELDFIX.)

Run `make selftest && make selftest-c` to confirm no regressions after workaround removal.

## Acceptance Criteria

- [ ] [transform.rb](../../transform.rb) contains a `block_given?` expansion block between the
  yield expansion and the `e.each_with_index` loop in `rewrite_env_vars`, matching:
  `e[0] == :call && e[1] == :"block_given?"` → sets `e[0] = :ne`, `e[1] = :__closure__`,
  `e[2] = 0`

- [ ] `make selftest` passes (no regression in MRI-compiled compiler)

- [ ] `make selftest-c` passes (no regression in self-hosted compiler)

- [ ] `./run_rubyspec spec/bug_block_given_nested_spec.rb` reports at minimum 3 passes and 0
  crashes for `block_given?` in single-nesting contexts (currently: 2 pass, 3 commented-out
  crashers). The doubly-nested and lambda cases are stretch goals; if they still crash, they
  remain commented out with updated notes.

- [ ] [compile_arithmetic.rb](../../compile_arithmetic.rb) no longer contains `bg = block_given?`
  — the pre-capture workaround is removed

- [ ] [compile_arithmetic.rb:129](../../compile_arithmetic.rb) uses `if block_given?` directly
  instead of `if bg`

- [ ] The `@bug` comment at [compile_arithmetic.rb:115](../../compile_arithmetic.rb) is removed

- [ ] `make selftest && make selftest-c` pass after the compile_arithmetic.rb workaround removal

## Open Questions

- **Does the lambda case (`check_bg_lambda`) require additional work?** Lambda bodies are
  processed by `rewrite_env_vars` via the `e[0] == :lambda` branch (line 701), which recursively
  calls `rewrite_env_vars(e[body_index], env)`. So `block_given?` inside a lambda should also
  get expanded by the same fix. However, the BUGAUDIT confirmed a segfault — test empirically.

- **Does doubly-nested work?** Inside `check_bg_doubly_nested`, there are two nested do-blocks.
  The inner block's `block_given?` needs to check the outermost method's closure. The env chain
  should propagate this via `aenv` passed to recursive `rewrite_env_vars` calls. Test empirically.

- **Interaction with YIELDFIX:** If YIELDFIX is applied before BGFIX, the `block.call` in
  `compile_arithmetic.rb` can be changed to `yield` at the same time as removing the `bg`
  pre-capture. If applied after, leave `block.call` in place. The plan accommodates both orders.

---
*Status: PROPOSAL - Awaiting approval*
