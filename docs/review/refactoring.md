# Refactoring Review — Structural Opportunities

Reviewed at commit `01234cd` (2026-07-04). Read-only review of the compiler's internal
machinery for *structural* refactoring (extraction, unification, normalization) — not
feature work. All claims below were re-verified against the current source; three new
live bugs were found and confirmed during the review (see "New evidence" — they are
symptoms of the structural problems, and the refactors below are shaped to kill the
whole class, not just the instances).

**Self-hosting constraint (applies to every item):** any change to transform.rb /
treeoutput.rb / compiler internals must keep `make selftest` AND `make selftest-c`
green, and refactors must use *proven* constructs. The code carries live workarounds
for known self-hosted miscompiles: no ternaries in hot paths (treeoutput.rb:282, :336),
no `seen |= x` (transform.rb:1366, :1619), no extra defaulted params on recursive
methods (rewrite_env_vars comment, transform.rb:1253–1257), no captured closure called
inside `.each` blocks (transform.rb:2105), `if !vars.empty?` segfaults where
`empty == false` works (transform.rb:1698). Function *size/layout itself* is a hazard:
`__rewrite_node_refs` was extracted from `rewrite_env_vars` specifically because the
combined function repeatedly miscompiled under self-hosting (transform.rb:1423–1427).
This cuts both ways: extraction is usually the *safe* direction, but every step needs
the full verification protocol (bottom of this doc).

---

## New evidence found during this review

These were verified by parsing/compiling test inputs against the current tree:

1. **`def f(a = 1); body; ensure; cleanup; end` miscompiles and crashes at runtime**
   with `undefined method 'block'`. The defm body arrives as the bare
   `[:block, args, stmts, rescue, ensure]` node; `rewrite_default_args`
   (transform.rb:3117–3130) iterates `body[k]` element-by-element, splicing the
   `:block` tag in as a statement and silently dropping the ensure/rescue structure.
   This is the **third** pass caught mishandling this shape, after `process_scope_env`
   (transform.rb:1561–1571) and `rewrite_keyword_args` (transform.rb:3011–3017) — the
   latter two were patched individually after the 32-file `__wrapenv` COMPILE_FAIL
   regression. Confirmed by compiling and running `/tmp/defens.rb`.

2. **safe-navigation comma mangles are still live.** The dot-comma normalization in
   `TreeOutput#oper` (treeoutput.rb:244–262) matches only `o.sym == :callm`, so with
   `&.` the comma list still binds into the method slot and nothing unmangles it:
   - `a, b = recv&.m, v` parses to `[:assign, [:destruct, :a, :b], [:safe_callm, :recv, [:m, :v]]]`
     — the RHS is a garbage dispatch (`[:m, :v]` as the method).
   - `f x&.m, v` parses to `[:call, :f, [[:safe_callm, :x, [:m, :v]]]]` — same mangle
     as a call argument.

3. **The `:callm`-shape unmangle branches in `oper` are now dead**, as suspected: with
   the dot-comma fix, `a.x, b.y = 1, 2` reduces to a normalized
   `[:comma, callm, callm]` before `:assign` fires, and `a, b = recv.m, v` reduces to a
   flat normalized RHS. The MLHS unmangle branch (treeoutput.rb:322–331 +
   `unmangle_mlhs_targets`) is, however, **still load-bearing for `:safe_callm`**
   (`a&.x, b = 1, 2` routes through it and comes out correct), and the RHS-twin branch
   (treeoutput.rb:300–321) matches only `:callm` so it appears fully unreachable.
   Do not delete anything until the safe_callm normalization (R4) is in.

---

## Findings

### R1. Normalize the defm/proc body shape ONCE, early in the pipeline
**What/where:** The bare `[:block, args, stmts, rescue, ensure]` body shape (produced
by the parser for `def ... rescue/ensure ... end`) is ad-hoc re-wrapped in
`process_scope_env` and `rewrite_keyword_args`, and is *mishandled* in
`rewrite_default_args` (live bug #1 above). Any future pass that concatenates onto or
iterates a defm body inherits the same trap.

**Why it matters:** Caused the 32-file `__wrapenv` regression (two passes disagreed on
the shape); causes the confirmed `default-arg + ensure` runtime crash; the shape test
itself (`body[0] == :block && body[1].is_a?(Array)`) is subtle because `:block` is also
a legal variable name (see the `single_node` contortion at transform.rb:1683–1696).

**Sketch:** Add one canonicalization pass at the *top* of `preprocess` (immediately
after `hoist_requires`): for every `:defm` (and `:proc`/`:lambda` body slot), if the
body is a bare `[:block, ...]` node, wrap it as `[[:block, ...]]` so bodies are ALWAYS
statement lists. Then delete the two local compensations and fix
`rewrite_default_args` for free (it prepends to a list that now really is a list).
Optionally add an `assert_body_shape` debug check the tests can enable.

**Risk:** Low. The two existing compensations become no-ops (wrap-if-not-wrapped), and
the change is confined to one new pass + two deletions. Main hazard is a pass that
*depended* on seeing the bare node (grep found none — `compile_defm` handles both).
**Effort:** 2–4 hours including a spec for the ensure+default crash.
**Priority:** Do before hard feature work (it directly fixes a live miscompile).

### R2. One scope-boundary predicate; unify the ten hand-maintained walkers
**What/where:** The review brief said four walkers; it is actually **ten** functions in
transform.rb carrying hand-maintained scope-boundary rules that must agree:
`__contains_proc_node?` (:958), `__contains_proc_node_defun?` (:601),
`__nest_proc_envs` (:573), `__repoint_creations` (:620), `__inject_wrapenv_prologue`
(:653), `find_vars` (:986), `__rewrite_env_vars_r` (:1264), `replace_bare_super`
(:2613), `__subst_method_name` (:2847), `rewrite_direct_ivars` (:1861) — plus 18
copies of `next :skip if e[0] == :sexp` across passes and the `:required` stop rules.
The boundary set is: `:defm` / non-`__lambda_` `:defun` / `:class` / `:module` /
`:sexp` / `:required`, with per-walker variations (lambda-defuns are transparent to the
`__nest_proc_envs` family; class bodies reset env depth; defm singleton receivers are
evaluated in the *enclosing* scope).

**Why it matters:** The 32-file regression was precisely a disagreement between these
walkers (find_vars didn't see lambdas inside a bare :block body, but
`__repoint_creations` did repoint them at a `__wrapenv` that find_vars never declared).
Every comment block in these functions is a post-mortem of a boundary disagreement
(rewrite_lambda's `next :skip if e[0] == :defm` was "the one pass that did not" treat
defm as a boundary — proc @addr corruption).

**Sketch (staged, in risk order):**
1. Introduce a single predicate module with two functions, written in proven
   constructs (plain defs, explicit loops, no closures):
   `scope_boundary?(n)` → `:method | :lambda | :class | :sexp | :required | nil`, and
   `lambda_defun?(n)` (the `n[0]==:defun && n[1] =~ /^__lambda_/` test, currently
   inlined five times).
2. Rewrite the four `__nest_proc_envs`-family walkers to consult it (they are the
   newest, most uniform, and pure-detection/mutation — lowest risk).
3. Provide one generic recursive `each_non_boundary(n, transparent_lambda_defuns,
   &block)` walker and port `replace_bare_super`, `__subst_method_name`,
   `rewrite_direct_ivars` onto it.
4. Only then have `find_vars` / `__rewrite_env_vars_r` *consult the predicate* for
   their skip decisions (do NOT restructure their traversal — they carry semantic
   actions at boundaries, not just skips).
A unit test should assert, for a table of node shapes, that every walker classifies
each boundary identically (this is the "must agree" property made executable).

**Risk:** Medium. Stage 1–3 are mechanical; stage 4 touches the most miscompile-prone
code in the tree. The predicate itself must not use case/when on arrays or ternaries.
**Effort:** 2–3 days including a rubyspec sweep before/after each stage.
**Priority:** Do before hard feature work — this is the highest-leverage change for
not repeating the regression class.

### R3. Characterize the latent self-host codegen bug: build a miscompile corpus
**What/where:** The tree contains at least a dozen *frozen reproductions* of the
layout-sensitive self-host miscompile, each preserved as a FIXME + workaround:
transform.rb:1235 ("putting the below on one line breaks"), :1366/:1619
(`seen |= x` fails), :1637 ("Removing the E[] causes segmentation fault"), :1698
(`if !vars.empty?` segfaults), :2105 (captured closure in .each breaks), 1253–1257
(extra defaulted params on a recursive method miscompiled), treeoutput.rb:282/:336
(ternaries), extensions.rb:33–51 (uninitialized-var + block-capture quirks in
depth_first), function.rb:129 (`r` not reset to nil), compiler.rb:592, :653, :1341,
:1346.

**Why it matters:** This is the single constraint that makes *every other refactor
here expensive*. Register pressure/spill in large functions is the working theory; it
has never been isolated. Each FIXME is a minimizable test case that currently only
exists as a comment — if the workaround is ever "cleaned up", the bug returns silently.

**Sketch:** (a) Extract each FIXME site into a standalone minimal .rb program in
`spec/selfhost/` that encodes the *broken* form (ternary, `|=`, defaulted recursive
param, one-lined return) with an expected-output assertion; run them through
`./compile2` (the self-hosted compiler) in CI so the failures are pinned and visible.
(b) Bisect one of them (the `seen |= x` form is smallest) down through `--parsetree` /
asm diff between `driver.rb` and `out/driver` output to name the actual codegen defect
(likely in regalloc.rb / register spill around subexpressions — 378 lines, small enough
to audit once a repro exists). Even without a fix, a *named* defect converts "known-
risky constructs" folklore into a checkable rule.

**Risk:** None to the product (test-only) until a fix is attempted.
**Effort:** 1–2 days for the corpus; the bisect/fix is open-ended (budget 2–3 days for
a first serious attempt, timebox it).
**Priority:** Do before hard feature work. Everything else's risk budget depends on it.

### R4. treeoutput.rb `oper()`: extend dot-comma normalization to `:safe_callm`, then delete the dead unmangles; split the 300-line if/elsif chain
**What/where:** `oper()` (treeoutput.rb:189–493) is a ~300-line reduce step mixing
operator translation, comma-precedence damage repair, MLHS reconstruction, block/
to_block plumbing, and hash/array grouping.

**Why it matters:** Verified live bugs #2 above exist *because* the callm fix wasn't
applied to safe_callm — per-shape patches in a monolithic chain don't propagate to
sibling shapes. The dead `:callm` unmangle branches (finding #3) are ~50 lines of
misleading code that new work must still reason about.

**Sketch:** (1) Make the dot-comma normalization branch (:244) match
`o.sym == :callm || o.sym == :safe_callm` (emitting the same `E[:comma, cm, rest]`
with the correct head tag) — this *fixes* both live bugs and makes the safe_callm MLHS
unmangle redundant as well. (2) Behind a temporary raise-if-hit assertion, run selftest
+ suite + rubyspec sweep; then delete `unmangle_mlhs_targets` and the two unmangle
branches (:300–331). (3) Split the chain into per-`o.sym` handler methods
(`oper_assign`, `oper_comma_repair`, `oper_collection`, ...) dispatched from a short
`oper` — extraction is the self-host-*safe* direction (see R3 preamble), but avoid a
Hash-of-lambdas dispatch (closures in this file are risky); a plain if/elsif over
`o.sym` calling named methods is enough.
**Risk:** Low-medium. Step 1 is additive; step 2 is guarded by the assertion period;
step 3 is mechanical extraction. Parser shapes are well covered by spec/.
**Effort:** ~1 day.
**Priority:** Do before feature work touching the parser/shunting yard; step 1 is a
bug fix and worth doing immediately.

### R5. Make the preprocess pass ordering explicit and testable
**What/where:** `Compiler#preprocess` (transform.rb:2634–2676): ~24 ordered passes
whose constraints live only in comments ("Must run BEFORE rewrite_strconst", "must
precede rewrite_symbol_constant (needs bare :sym args)", "before
rewrite_splat_to_array mangles the lvalue", ...). `rewrite_pattern_matching` runs
*outside* preprocess (in `compile`, after find_vars) — which is itself the documented
cause of the pattern-binding/nested-closure limitation (transform.rb:19–22).

**Why it matters:** The ordering comments encode ~10 hard constraints; violating any
is a silent miscompile. There is no test that fails if someone reorders. The fragility
tax shows in how new passes get inserted (each new one repeats the archaeology).

**Sketch:** Replace the call sequence with a declared pass list — a constant array of
`[:name, [:before, :x], [:after, :y]]` entries and a tiny runner that (a) executes in
listed order, (b) asserts the declared constraints are satisfied by the listing (cheap
topological check at startup in test mode only). Keep each pass a plain method call —
no lambdas (self-hosting). Add characterization tests: for each documented constraint,
a minimal source snippet that miscompiles/crashes when the constraint is violated
(these can be MRI-hosted unit tests asserting on the transformed tree, no compilation
needed — cheap and fast). Fold `rewrite_pattern_matching` into the manifest with an
explicit `:late` stage annotation and a comment pointing at the KNOWN_ISSUES entry, so
its odd position is declared rather than incidental.
**Risk:** Low — the runner executes the identical sequence; only test surface is added.
**Effort:** 0.5–1 day.
**Priority:** Do before feature work that adds passes (i.e., most feature work).

### R6. Canonicalize call-argument shape (kill the "bare single argument" quirk)
**What/where:** The parser leaves a single non-array argument bare in the args slot
(`[:call, :m, :pattern, block]` instead of `[:call, :m, [:pattern], block]`), and a
sole `[:hash]`/`[:array]` literal unwrapped. At least NINE sites compensate:
`rewrite_strconst`, `rewrite_integer_constant`, `rewrite_symbol_constant`,
`__rewrite_node_refs` (the four `e[i] = E[e[i]] if is_call && i > 1` fixups),
`group_keyword_arguments` (:731), `rewrite_class_new` (:1888), `rewrite_splat_to_array`
(bare check), `compile_call` (:315), `compile_callm` (:500), `compile_assign` (:870) —
each with its own variant of the "is args[0] a node tag?" test
(`@@keywords.include?(args[0]) || [:call, :callm, :safe_callm, :lambda, :proc]...`, 8
copies across 3 files). The compensations have *diverged*: compile_callm's has an
`args.length > 1` guard (added for `obj.m(pattern) do..end`) that compile_call's lacks
— currently benign only because the parser happens to hand `:call` its single argument
bare rather than as a one-element list (verified), i.e. correctness rests on an
undocumented shape difference between two parser paths.

**Why it matters:** This quirk is the direct cause of a long tail of historical bugs
(the comments cite: "wrong number of arguments" from env-rewritten bare args, the
`m({...}) { }` bogus nested-hash, `undefined method 'do'/'callm'` tag-iteration, the
`obj.m(pattern) do..end` keyword-named-variable dispatch). Every new pass that touches
call args must rediscover it.

**Sketch:** Two options; prefer (a):
(a) A canonicalization pass early in preprocess (right after R1's body normalization):
walk `:call`/`:callm`/`:safe_callm` nodes and force the args slot to always be a
proper list of argument nodes (wrapping bare singles, wrapping sole hash/array
literals). The nine compensations become no-ops immediately and can be deleted
incrementally, each deletion verified by suite+selftest.
(b) Fix at the source in treeoutput/shunting (where the single-arg wrap is skipped on
the block path) — cleaner but riskier since raw-parse consumers (`print_sexp`,
`--parsetree` diffs, tests asserting parse output) see the change.
Extract the shared `ast_node_tag?(sym)` predicate regardless (one definition instead
of 8).
**Risk:** Medium. The canonical pass touches every call node; the danger is a consumer
that *relies* on bareness (compile_call's arity of the `[args]` wrap, splat handling).
Mitigate by deleting compensations one at a time, sweep between.
**Effort:** 2–4 days spread out (pass + predicate in half a day; the deletions are the
long tail).
**Priority:** Opportunistic-but-soon; do after R1/R5 so the pass has a declared slot.

### R7. Extract the shared machinery of compile_call / compile_callm
**What/where:** compile_calls.rb:220–342 and :470–596. Beyond the arg-shape
duplication (R6), the two share: the no-op visibility/attr method sets (two divergent
lists — compile_call's includes `:undef_method, :private_constant, ...`,
compile_callm's doesn't), the `:to_block` → block-slot pop with `&:sym` to_proc
conversion (callm only — compile_call *doesn't* handle `f(&:sym)`; worth a test),
yield/super redirection, and self-reload/evict postamble.

**Sketch:** Extract `normalize_call_args(args, block, for_callm:)` (subsumed by R6 if
done), `noop_class_body_method?(func, scope)` (one set, one scope test — also fixes
the LocalVarScope-wrapped-ModuleScope case only being handled in compile_call),
and `pop_to_block!(args)` used by both. Keep the codegen bodies separate — the
callm vtable dispatch vs call addressing genuinely differ.
**Risk:** Low-medium (compile-side, fully exercised by selftest + suite).
**Effort:** ~1 day.
**Priority:** Opportunistic; bundle with any planned work in compile_calls.rb.

### R8. Unify the splat/&block parameter prologue between process_scope_env and rewrite_lambda
**What/where:** `rewrite_lambda` (transform.rb:449–536) hand-mirrors
`process_scope_env`'s rest-param prologue (`__splat_to_Array`, trailing-param
rebinding from the arg tail, &block binding) with an ABI offset difference (3-slot
prefix vs 1) — the comments literally say "Mirrors the :defm handling in
process_scope_env". Two copies of the trailing-param index arithmetic
(`numargs - ac - 2 + j`) must stay in sync; one already drifted once (the lambda path
"never got" the prologue at all until patched).

**Sketch:** Extract `build_splat_prologue(params, fixed_slot_count, let_target)`
returning the assign list, parameterized on the prefix width; both callers consume it.
Same for the &block nilable-binding snippet.
**Risk:** Medium — this is deep in the env machinery; but it is a pure
same-output extraction, verifiable by diffing `--parsetree` output over the test corpus
before/after (should be byte-identical).
**Effort:** 1 day including the parsetree-diff harness (which is itself reusable for
every transform.rb refactor — consider building it first; it makes R1/R2/R6
regressions visible without compiling).
**Priority:** Opportunistic; the parsetree-diff harness sub-item is do-before.

### R9. Scope#get_arg protocol cleanup (classcope/globalscope special cases)
**What/where:** The `get_arg` resolution protocol across scope.rb, classcope.rb,
globalscope.rb, funcscope.rb, localvarscope.rb, eigenclassscope.rb, sexpscope.rb
returns bare tuples with at least 10 tags (`:lvar/:arg/:argaddr/:global/:ivar/:cvar/
:possible_callm/:addr/:runtime_const/:reg/:int`), sometimes wrapped in `Value`,
sometimes nil (base `Scope#get_arg` returns nil; ClassScope then does `n[0]` on it —
guarded only by evaluation order at classcope.rb:221). Known warts, each currently
load-bearing: the `(?A..?Z).member?` constant test ("Hacky way of excluding
constants") duplicated in 3 files; ClassScope#get_constant's `a.to_s.include?("__")`
"probably fully-qualified" heuristic (breaks for any user constant containing `__`);
SexpScope#get_arg's documented reliance on `Integer#[]` bit-indexing never equaling
`:possible_callm`; the classcope.rb:221 `n[0] == :global` check running before the
`n &&` nil-guards.

**Sketch:** Not a rewrite — a tightening: (1) one `constant_name?(sym)` helper used
everywhere; (2) make every `get_arg` return a tuple, never nil (base returns
`[:addr, a]` like the leaves already do), then simplify the callers' guards;
(3) SexpScope: test `arg.is_a?(Array) && arg[0] == :possible_callm` and delete the
smell comment; (4) replace the `include?("__")` heuristic with an explicit
`fully_qualified?` flag threaded from the callers that *construct* mangled names
(build_class_scopes/flatten_deref are the only producers). (4) is the only risky one —
do it last, standalone.
**Risk:** Low for 1–3, medium for 4.
**Effort:** 1–2 days.
**Priority:** Opportunistic — but do 1–3 before touching constant resolution for
features (namespacing work will otherwise build on the heuristic).

### R10. Value/type system: make the :object/raw distinction explicit and audited
**What/where:** value.rb (`Value < SimpleDelegator`, `@type ∈ {:object, nil}`),
`lookup_type` (compiler.rb:130–147), consumers `compile_jmp_on_false/true`
(compile_control.rb:4, :25) and `combine_types` (compiler.rb:525). Truthiness is
load-bearing: an untyped (nil) value gets C truthiness (`testl`), so a `false` object
(nonzero pointer) is truthy — this exact failure took out self-compilation once
(lookup_type's own comment: env-slot reads typed raw made `do_load_super` call
`false.to_sym`). Meanwhile `get_arg` types *every* symbol resolution `:object`
(compiler.rb:201–205, both under "FIXME: Need to check type"), so the raw path is
reached mainly via `%s(...)` sexps and arithmetic — but `combine_types` silently
degrades to nil when arms disagree, and `Value#is_a?` is deliberately "evil"
(delegates to the wrapped object), so a `Value` is invisible to `is_a?(Value)` checks.

**Sketch:** Keep semantics identical; add guardrails: (1) name the raw type — use
`:raw` instead of nil so a *missing* type is distinguishable from an *intended* raw
type; accept nil as :raw during migration. (2) Centralize the truthiness decision in
one `truthy_jmp(scope, r, target, invert:)` used by both jmp helpers (they are near-
copies). (3) Make `combine_types` warn (in MRI-hosted debug mode) when it degrades a
typed/untyped mix — those sites are exactly where the next `false`-is-truthy bug will
come from. (4) Unit-test `lookup_type` directly (env-hop unwrap, slots 0/1 raw).
**Risk:** Low (behavior-preserving; nil stays accepted).
**Effort:** 0.5–1 day.
**Priority:** Do the cheap parts before any typing/feature work builds on Value;
a real type lattice is out of scope and not currently needed.

### R11. Decompose find_vars (opportunistic, after R2)
**What/where:** `find_vars` (transform.rb:986–1240, ~255 lines) is a single recursive
function with a giant per-node-tag elsif chain (assign/lambda/class/callm/call/deref/
block/case/default), threading 7 positional state params (`scopes, env, freq,
in_lambda, in_assign, current_params`) — recall that *adding defaulted params to a
recursive method is itself a known self-host miscompile vector* (R3), which makes this
function structurally dangerous to extend: the next node type that needs special
handling (e.g. the :case fix's sibling shapes) means growing it again.

**Sketch:** After R2's boundary predicate exists: move the per-tag branches into
`find_vars_assign`, `find_vars_lambda`, `find_vars_case`, ... each taking an explicit
small state object (a plain class with attr_accessors — proven construct — instead of
7 params). The dispatcher stays one page. Verify with the R8 parsetree-diff harness
(find_vars has no output of its own, but its effects show in the let/env layout of the
transformed tree, which the harness captures).
**Risk:** Medium-high — this is the heart of closure capture. Only worth doing when a
concrete need to extend it appears; do NOT bundle with R2 stage 4.
**Effort:** 2–3 days.
**Priority:** Opportunistic.

### R12. Noted but not recommended now (architectural)
- **vtableoffsets / global vtable layout** (vtableoffsets.rb): every method name in
  the program gets one global slot and every class object is `@vtableoffsets.max`
  slots — memory scales O(classes × global-method-names), and `clean_name`'s
  unwrap-first-element loop is a foot-gun for array-shaped names. A per-class layout
  or selector-coloring scheme is a *large* project entangled with `__send__` fallback,
  method_missing thunks and the `__voff__` link-time protocol. Leave until it hurts
  (binary size / startup), then design properly.
- **E/AST::Expr vs raw Array** (ast.rb, extensions.rb): `depth_first` lives on Array
  with a FIXME to move it to Expr "when the parser never creates raw arrays"; position
  tracking is best-effort (`update_position` has a latent bug: it assigns a *local*
  `position` at ast.rb:63, not `self.position` — harmless only because callers mostly
  pass positions explicitly). Fixing the assignment is a one-liner worth doing; the
  Expr-everywhere migration is opportunistic and large.
- **ModuleScope CLASS_IVAR_NUM / @ivaroff bootstrap coupling** (classcope.rb:27,
  :40–42): "can only safely be determined after we've parsed everything" — known
  reopened-superclass hazard, documented. Needs a two-phase layout pass; bundle with
  any future object-layout work, not standalone.

---

## Top 10 by payoff vs risk

| # | Item | Payoff | Risk | Effort | When |
|---|------|--------|------|--------|------|
| 1 | R1 defm-body shape normalization (+ fixes live ensure+default crash) | High | Low | 2–4 h | **Before feature work** |
| 2 | R4 step 1–2: safe_callm dot-comma normalization (+ fixes 2 live bugs), then dead-branch removal | High | Low-Med | 1 d | **Before feature work** |
| 3 | R3 self-host miscompile corpus (`spec/selfhost/`) + one timeboxed bisect | High (unblocks all) | None (tests) | 1–2 d (+2–3 d bisect) | **Before feature work** |
| 4 | R2 unified scope-boundary predicate, staged over the 10 walkers | Very high | Med | 2–3 d | **Before feature work** |
| 5 | R5 preprocess pass manifest + ordering-constraint tests | Med-high | Low | 0.5–1 d | **Before feature work** |
| 6 | R8 parsetree-diff harness (sub-item) then splat-prologue unification | Med | Med | 1 d | Harness before; rest opportunistic |
| 7 | R10 truthiness centralization + `:raw` type naming | Med | Low | 0.5–1 d | Before typing-adjacent work |
| 8 | R6 call-arg canonicalization pass + `ast_node_tag?` extraction | High (long-term) | Med | 2–4 d | Opportunistic-soon, after R1/R5 |
| 9 | R7 compile_call/compile_callm shared helpers (incl. no-op-set divergence, `f(&:sym)` gap) | Med | Low-Med | 1 d | Opportunistic |
| 10 | R9 get_arg protocol tightening (constant_name?, nil-free returns, SexpScope) | Med | Low (part 4 Med) | 1–2 d | Opportunistic |

R11 (find_vars decomposition) and R12 (vtable layout, Expr migration, ivar-offset
bootstrap) are deliberately below the line: high blast radius, no current forcing
function. The ast.rb `update_position` one-liner from R12 is worth slipping into any
nearby change.

## Verification protocol for every item above
1. `make selftest` (MRI-compiled compiler runs test/selftest.rb) and
   `make selftest-c` (self-compiled compiler compiles and runs it) — both green,
   non-negotiable.
2. The spec/ suite (`rake test`) — parser/transform shape regressions.
3. Full rubyspec sweep (`bin/ax52-specs`) compared against the current baseline;
   judge on the deterministic COMPILE_FAIL/TIMEOUT lists, and re-run flaky CRASH
   entries in isolation (`setarch -R`) before attributing regressions.
4. For transform.rb-only refactors, prefer the parsetree-diff harness (R8): identical
   `--parsetree` output over the corpus is a much stronger and faster check than
   end-to-end runs.
5. After any change to transform.rb hot paths, treat a selftest-c *hang or wrong
   output with green MRI-hosted selftest* as the layout-sensitive miscompile (R3):
   don't debug the refactor logic first — check the known-risky constructs list.
