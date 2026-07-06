# Closure environments, block channels, and non-local control flow

*Written 2026-07-04, after the nested-environment rework (`c6d1f4f`) and the
block-channel de-globalization (`63b5875`). This is the design doc for the
subsystem where the transform walkers MUST agree or selftest-c dies — the
`620a91b` regression was exactly four walkers disagreeing about scope shapes.*

## 1. Environment layout

Every activation that captures variables (or allocates a wrapper — see §3)
carries an `__env__` local pointing at a heap-allocated env object with a
UNIFORM layout:

| Slot | Name | Contents |
|---|---|---|
| 0 | `__stackframe__` | %ebp of the activation that ALLOCATED this env. This is `break`'s unwind target and `preturn`'s root anchor. |
| 1 | `__envparent__` | The enclosing env (0 at the root — envs come from calloc, so no explicit init). |
| 2.. | captured vars | Only in the ROOT env of a method/top-level scope. Captured variables always live in the root env; wrapper envs are just `[frame, parent]`. |

In a method scope, slot 2 by convention holds `__closure__` — the block passed
to the METHOD (see §4). The root env is allocated by the `__alloc_env N` call
injected in the prologue by `process_scope_env` (transform.rb), which also
copies captured parameters into their slots.

## 2. Variable references and hops

`__rewrite_env_vars_r` (transform.rb) rewrites references to captured
variables into env slot accesses. A reference at nesting depth `d` (d = number
of wrapper envs between the referencing lambda and the root) becomes a
hop-chained index:

```
depth 0:  [:index, :__env__, N]
depth 2:  [:index, [:index, [:index, :__env__, 1], 1], N]
```

built by `__env_hops(depth)` — each `[:index, ..., 1]` follows one
`__envparent__` link. Depth is threaded through the pass in IVARS
(`@env_depth` / `@env_in_lambda`), NOT extra defaulted parameters on the
recursive method — adding defaulted params to a recursive method is a known
self-host miscompile vector (see §8).

**Type rule:** `lookup_type` (compiler.rb) must UNWRAP hop chains to recognize
an env access: slots 0/1 are raw machine words; slots ≥2 are `:object`. Typing
a hop-chained read raw makes a `false` OBJECT (a nonzero pointer) truthy in
`&&`/`if` — this broke self-compilation once (repro: test/repros/hop1.rb).
`class_body_env_size` (compile_class.rb) does the same unwrap when sizing
class-body envs.

## 3. Wrapper envs and `__wrapenv`

A lambda that itself CREATES a proc/lambda needs its own activation record for
re-entrancy (threads/fibers): each invocation must give its inner procs a
fresh frame pointer to unwind to. Such lambdas allocate a 2-slot wrapper env
`[own frame, parent env]` at entry.

Mechanics (all in transform.rb):
- `find_vars` declares the let-locals `:__tmp_proc` and `:__wrapenv` for a
  scope when `__contains_proc_node?` detects a proc-creating lambda below it.
- After `rewrite_lambda` converts blocks to `:defun`s, the post-pass
  `__nest_proc_envs` walks lambda defuns (`__contains_proc_node_defun?`,
  `__repoint_creations`, `__inject_wrapenv_prologue`): it injects the
  `__wrapenv = __alloc_env(2); wrapenv[0] = frame; wrapenv[1] = __env__`
  prologue and repoints each proc-CREATION triple
  (`[:do, guard-if, [:assign, :__tmp_proc, [:defun ...]],
  [:sexp, [:call, :__new_proc, ...]]]`) to pass `__wrapenv` as the new proc's
  env instead of the (root) `__env__`.

**The detectors must agree.** The pre-conversion detector (`find_vars` /
`__contains_proc_node?`) decides whether `__wrapenv` is DECLARED; the
post-conversion detector family decides whether creations are REPOINTED. Any
shape one sees and the other doesn't produces "undefined reference to
__wrapenv" COMPILE_FAILs (the 32-file regression) or silently unrepointed
procs.

## 4. Block channels (no globals)

Two distinct block channels exist, and they must not be conflated:

**The METHOD's block (`__closure__`).** Method defun ABI is
`(self, __closure__, *args)`. `yield` and `block_given?` inside the method —
and inside any BLOCK nested in the method — reach the method's block through
the env-captured `__closure__` (slot 2 of the root env). `rewrite_block_given`
is a transform pass that expands `block_given?` before env capture so the
reference boxes per-context; it must NOT rewrite method-NAME slots (e.g.
`Kernel.block_given?`).

**The CALL-TIME block (`__callblk__`).** Lambda/block defun ABI is
`@addr(self, __callblk__, __env__, *args)` — slot 2 carries the block passed
to THIS invocation of the proc (`pr.call { ... }`), nil when none.
A block's own `&b` parameter binds from `__callblk__`
(`[:assign, bname, :__callblk__]` in `rewrite_lambda`). `Proc#call`/`#[]`
pass their `&blk` straight into the slot:

```ruby
def __call_with_self newself, blkarg, *__copysplat
  %s(call @addr (newself blkarg @env (splat __copysplat)))
end
```

`__call_with_self` cannot take `&blk` itself — its raw `(splat __copysplat)`
marshalling assumes the signature is exactly (fixed..., *rest) — so the block
travels as the EXPLICIT `blkarg` fixed parameter. **Every caller must pass it**
(nil when none): forgetting it shifts user arguments into the block channel
(that was the instance_exec bug, `17dffc5`; repro test/repros/ie1.rb).

**Never name a local `__closure__` in a method body** — env-boxing of that
name corrupts splat counts (learned during 63b5875; see also the transform.rb
guard).

## 5. break, return-from-proc (preturn), and ensure

- **`break`** compiles to a jump that unwinds to `__env__[0]` — the frame of
  the activation that ALLOCATED the block's env. Under nested envs that is the
  DEFINING activation (per-invocation wrapper env), so `break` resumes right
  after the yielding call with MRI semantics, re-entrantly
  (repro: test/repros/bk6.rb).
- **`return` inside a proc** (`preturn`) must return from the DEFINING METHOD:
  the emitted asm walks `__envparent__` links to the root env and unwinds to
  ITS slot-0 frame (compile_preturn, compiler.rb).
- **`return` inside a lambda** stays local — `rewrite_proc_return` treats
  `:lambda` as a boundary and rewrites only proc returns.
- **`return` through ensure**: compile-time `@ensure_stack` (compiler.rb) is
  pushed around begin/rescue try-bodies; `compile_return` unwinds it — pops
  exception handlers and runs ensure bodies with %eax (the return value)
  preserved (`46a78f6`).

## 6. Scope boundaries — the rule every walker must implement

The transform walkers that traverse into nested code must stop (or reset
state) at:

| Boundary | Why |
|---|---|
| `:defm` | New method scope (its own env; singleton-receiver slot is evaluated in the ENCLOSING scope) |
| `:defun` not named `__lambda_*` | Real function; `__lambda_*` defuns are converted blocks and are TRANSPARENT to the nest walkers |
| `:class` / `:module` | Class bodies REBIND `__env__` parentless — depth and in_lambda reset there in both analysis passes |
| `:sexp` | Raw asm — never rewrite inside |
| `:required` | Un-hoisted require marker |

Ten functions in transform.rb currently hand-maintain this list
(`__contains_proc_node?`, `__contains_proc_node_defun?`, `__nest_proc_envs`,
`__repoint_creations`, `__inject_wrapenv_prologue`, `find_vars`,
`__rewrite_env_vars_r`, `replace_bare_super`, `__subst_method_name`,
`rewrite_direct_ivars`). Unifying them behind one predicate is refactoring
item R2 (see review/ANALYSIS.md, Phase 4). Until then: **any new walker must
implement the table above exactly, and any boundary change must be applied to
all ten.**

Node-shape guards that go with this:
- `:lambda`/`:proc` shape test is `n[1].nil? || n[1] == :block || n[1].is_a?(Array)`
  — a LET var-list starting with a local named `lambda`/`proc` is a false
  positive otherwise.
- defm/proc/lambda bodies are ALWAYS statement lists after the
  `normalize_body_shape` pass (R1) at the top of preprocess; the historical
  bare `[:block, args, stmts, rescue, ensure]` body shape appears only in
  nodes CONSTRUCTED by later rewrites (per-pass wrap-if-bare guards remain).
- `Class.new sup do..end` parses the paren-less arg as a BARE node, not a
  list — watch for this in any `e[3]`-inspecting rewrite.

## 7. Pattern-matching interaction (open)

`rewrite_pattern_matching` runs OUTSIDE preprocess, after `find_vars`, so
pattern bindings (`in [a, b]`) referenced inside a block are not env-captured
and resolve as method calls (KNOWN_ISSUES active issue 2; repro
test/repros/pm1.rb). Fixing this means running it earlier or registering its
lvars with capture analysis.

## 8. Self-hosting hazards learned in this subsystem

All of these MISCOMPILE under self-hosting (selftest-c) while working under
MRI — check this list before debugging transform logic:
- Ternaries in hot transform paths; `seen |= x`; `if !vars.empty?` where
  `empty == false` works.
- Extra DEFAULTED parameters on a recursive method (thread state via ivars
  instead).
- Oversized functions: layout-sensitive miscompiles — extraction is the safe
  direction (`__rewrite_node_refs` exists because of this).
- `:"#{expr}"` symbol literals do not interpolate self-hosted — build with
  `"...#{}".to_sym`.
- `[:assign, [:global, name], value]` is not a valid lvalue — use a
  `$`-prefixed symbol (auto-registers).
- Never `ruby -i` on compiler sources; never edit sources while a gate chain
  or battery is running.

## References
- review/ANALYSIS.md — Phase 4 R2 (walker unification; R1 shape-normalization done)
- docs/bugs/RESOLVED_INVESTIGATIONS.md — the env/`__tmp_proc` slot-aliasing
  and eigenclass corruption post-mortems
- test/repros/ — bk6, hop1, ie1, pm1, blk1 exercise this subsystem
- test/selftest.rb yield-rewrite expectation (`__alloc_env, 3`, guard shape)
