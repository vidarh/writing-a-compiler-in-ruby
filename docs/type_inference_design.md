# Type-inference for emitted-code quality — design & status

Living design doc for the type-inference performance work (dispatch + arithmetic). Written
2026-07-12/13. Goal: speed up compilation (MRI-hosted **and** self-hosted) by improving the quality of
the emitted code, using **generic** whole-program type analysis. Companion memory:
`compiler_dispatch_perf_directions`, `feedback_no_hardcoded_inline_checks`,
`compiler_infer_nonfixnum_inline_asm_hole`.

## Hard constraints (from the user)

1. **Optimizations MUST be generic.** No per-method baked-in semantics (e.g. "Symbol#=== is identity").
   A `case x when :sym` → raw-`eq` special-case was implemented and **rejected/forbidden**: even with a
   Symbol#===-redefinition gate it hardcodes an expectation of one method and is a bespoke special-case,
   not generic machinery. The generic form must **derive** the optimization from the program's ACTUAL
   method definitions (resolve the real method, prove it stable, then direct-call/inline it) — the
   mechanism may then optimize Symbol#=== as a *consequence*, never because it was told what === does.
2. **Bootstrap-critical changes need a full sweep before commit.** Gates (`make selftest` +
   `make selftest-c`, both Fails:0) are necessary but NOT sufficient — they don't exercise the diverse
   spec patterns that expose unsoundness. The parallel sweep crash list is ASLR-flaky, so use `setarch -R`
   for deterministic repros. Baseline crash set to match: PASS 550, CRASH 9, COMPILE_FAIL 1, TIMEOUT 9
   (docs/spec_status.md).

## Status

- **Phase 1 — method-local non-fixnum inference (fixnum-guard elision): LANDED + SOUND** (commit
  22ebdd8). `infer_nonfixnum_locals` (compile_calls.rb) proves which locals always hold a heap
  (non-fixnum) value so `receiver_never_fixnum?` can drop the `load_class` fixnum guard for those
  receivers. The earlier revert (88835d3) was a real unsoundness — `next :skip if t == :sexp` skipped
  inline-asm `(assign local ...)` writes (Array#each's `%s(assign el (index @ptr (sar i)))` stores a raw,
  possibly-fixnum element into `el`), so `el` was wrongly inferred non-fixnum → guard elided → `[1].each`
  SIGSEGV. Fix: scan `:sexp` subtrees and taint every `(assign SYM ...)` target. Full sweep after the fix:
  crash set identical to baseline (zero regressions).
- **MEASURED: Phase 1 is perf-NEUTRAL.** Self-hosted self-compile of driver.rb: 14.76s with elision vs
  14.55s without (elision if anything slightly slower — the inference's compile-time cost ≈ the saved
  guards). **Reason:** the fixnum guard (`movl Fixnum; testl $1,%esi; jne`) is a *well-predicted branch*,
  ≈ free. The real dispatch cost is the **vtable read** (`call *off(%eax)` — the cache-missing indirect
  load), which guard-elision does NOT touch. **Corollary: do not extend the guard-elision line for
  speed.** All guard-elision variants (Phase 2 param inference, Phase 3 return inference) share this
  neutrality — a predicted branch is free regardless of how we prove it dead.

## The real lever: skip the vtable read (devirtualization)

Ruby operators/method calls compile to `[:callm, recv, m, [args]]` → `call *off(%eax)` (vtable read +
indirect call). Even arithmetic: `a + b` → `(callm a + (b))` → dispatch to Integer#+. To beat this we must
**statically resolve** the call to the actual method and emit a **direct** `call __method_<Class>_<m>`
(and later inline it), skipping the vtable read. This is the generic type-inference application.

### Machinery that exists
- `@classes[name]` (compiler.rb) → ClassScope; `.vtable[m]` → VTableEntry(.offset,.realname,.function),
  `.superclass`.
- Method label scheme (compile_class.rb:24): `__method_#{scope.name}_#{clean_method_name(m)}` —
  DETERMINISTIC, so a resolved (class,method) label can be constructed directly (no registry query
  needed at emit time).
- Call site: compile_calls.rb — `@e.callm(m)` (the vtable dispatch) at ~line 726; replace with
  `@e.call(label)` when devirt-eligible. Minimal change: keep arg setup identical (the vtable entry
  *points to* that label; calling convention is identical), just swap the indirect call for a direct one.
  The `load_class` above it becomes dead but harmless in v1; drop it later.

### Timing problem
`alloc_vtable_offsets` (compiler.rb:1785) allocates only GLOBAL per-NAME vtable offsets; it does NOT build
a per-class method map, and `@classes[C].vtable` fills incrementally during `output_functions`. So devirt
needs a NEW up-front pre-pass (run in `compile` right after alloc_vtable_offsets) that walks
`[:class, C, sup, *body]` recording, per class, each directly-defined `[:defm, m, ...]`.

### Receiver-class knowledge (generic)
- **Typed literals** give an EXACT class with zero flow analysis: `[:array]`→Array, `[:hash]`→Hash,
  `[:float]`→Float, string `[:sexp,[:call,:__get_string,_]]`/`[:sexp,:__FSL..]`→String,
  `[:sexp,:__S_..]`→Symbol. (This is the safe first foothold; the big prize is FLOW inference of
  variable/result receiver classes — a large, separate project.)

### Soundness — the key lever
A method defined **directly on class C** always out-ranks anything inherited (Object, included modules;
`prepend` is a no-op in this compiler). So for `<C-literal>.m` where **C defines m directly**, the ONLY
things that can change what runs at runtime are, all detectable in the AST:
1. **A second direct def** of C#m (reopening `class C; def m`). → require direct-def count == 1.
2. **alias/undef of m on C** — `[:alias, m, _]` inside `class C`, `[:undef, m]` inside `class C`.
3. **define_method targeting C** with name m.

Crucially, define_method/alias/undef targeting a DIFFERENT class D (D≠C) can NOT disqualify C#m, because
C's own direct method wins. This is what makes per-class precision both necessary and achievable.

### define_method reality (why global-disable is a dead end, and per-class is needed)
A global "any define_method → disable devirt" rule fires NOWHERE: the rubyspec helper (required by EVERY
spec) does `Object.send(:define_method, name)` (rubyspec_helper.rb:1348), and lib/core uses define_method
in Struct/Data/Class/Object. Catalogue of the ACTUAL define_method sites and their targets:
- **rubyspec_helper.rb:1348** `Object.send(:define_method, name)` → target **Object**, dynamic name. Adds
  an Object method → does NOT shadow any literal class's OWN direct method. Irrelevant to devirt of
  direct-on-C methods.
- **struct.rb:71 / data.rb:25** `klass.class_eval(&block)` where `klass = Class.new(...)` → a **fresh
  anonymous** class, never a literal class. Irrelevant (needs "klass is Class.new" to prove, or a
  conservative "anonymous/local receiver, not a literal-class constant" rule).
- **object.rb:180** `sc.send(:define_method, name, pr)` where `sc` is a **singleton class** → installs a
  SINGLETON method, does NOT affect instance-method dispatch. Irrelevant to instance-method devirt.
- **class.rb:519,528** `define_method sym` / `define_method "#{sym}=".to_sym` inside
  `attr_reader`/`attr_writer`/`attr_accessor` → target is the class that CALLS attr_* (self), names are
  the attr symbols. Disqualifies (C, attr-name) only for classes C that call attr_* with that name. These
  method names are NOT `[:defm]` defs, so they never enter the direct-def set anyway — but a NAME that is
  both attr'd and directly-def'd on the same C must be excluded.
- **class.rb:465** `def define_method` etc. are the DEFINITIONS of these primitives, not uses.

**Sound generic per-class rule (target resolution):** a define_method/alias/undef call disqualifies
literal class C#m only if its target is provably-or-possibly C. Resolve the target:
- explicit constant receiver `Array`/`String`/… → that class;
- textual `class C … define_method`/`alias`/`undef` (self==C) → C;
- `X.class_eval{…}` / `X.send(:define_method,…)` → X (constant → that class; `Class.new`/anonymous/local
  var → NOT a literal class, safe to ignore; unresolvable var → conservative);
- bare `define_method`/`attr_*` inside a method body → self is dynamic; sound conservative handling =
  treat as "could be any class that invokes this method" → needs a (cheap) call-graph/whom-calls-attr_*
  check, OR conservatively disqualify the specific attr NAMES program-wide (attr names rarely collide
  with directly-def'd literal-class methods).
A `singleton_class`/`obj.send` on a per-object singleton NEVER affects instance dispatch → always safe to
ignore. String eval → none in the self-compile and unsupported by the compiler → treat absence as given.

**VERIFIED 2026-07-13 — this is simpler than feared for the literal classes.** The literal classes
(Array/String/Hash/Float/Symbol) do NOT call `attr_accessor`/`attr_reader`/`attr_writer` anywhere in
lib/core (grep: the only hit is a *comment* in string.rb:7). So the one genuinely-hard site (the
dynamic-`self` `define_method` inside `attr_*`) provably never targets a literal class → it cannot
disqualify any literal-class direct method. That removes the need for an `attr_*` call-graph. With that
gone, the remaining define_method targets for the self-compile are all provably-not-a-literal-class:
`Object.send(:define_method)` (→ Object), `klass.class_eval` on a `Class.new` (→ fresh anon class),
`sc.send(:define_method)` (→ singleton, no instance effect). **Net: literal-class direct-method devirt is
sound with a MODEST analysis** — the target-resolution only needs to (a) treat an explicit constant
receiver as that class, (b) recognize `Class.new`/anonymous/singleton receivers as non-literal, and (c)
disqualify a literal class C only on a `class C … def/alias/undef/define_method` or `C.<meta>` that names
it. No deep call-graph/data-flow required for the v1 literal-class slice. (Flow inference is still needed
later for VARIABLE receivers — the big prize — but not for this first sound slice.)

## Analysis passes (generic; sketched + validated)

Validated on a self-compile via a since-reverted env-gated pass (`DEVIRT_ANALYZE`). Measured surface
(self-compile = driver.rb + full lib/core): 181 classes; 53 distinct alias/undef method NAMES; a dynamic
define_method IS present. Direct-defined / defined-EXACTLY-once per literal class: **Array 159/158,
String 147/146, Hash 104/102, Float 64/64, Symbol 29/29, Integer 188/176** → a large eligible surface,
gated only on getting the define_method target resolution right.

```
# per-class direct [:defm] counts (stops at nested class/module/defm)
def compute_class_direct_methods(exp)      # {class_sym => {method_sym => count}}
  out = {}
  exp.depth_first(:class) do |cnode|
    cname = cnode[1]
    if cname.is_a?(Symbol)
      out[cname] = {} if !out[cname]
      i = 3                                  # [:class, name, superclass, *body]
      while i < cnode.length; scan_direct_defms(cnode[i], out[cname]); i += 1; end
    end
    nil
  end
  out
end
def scan_direct_defms(node, counts)
  return if !node.is_a?(Array)
  t = node[0]; return if t == :class || t == :module
  if t == :defm
    m = node[1]; counts[m] = (counts[m] || 0) + 1 if m.is_a?(Symbol); return
  end
  i = 0; while i < node.length; scan_direct_defms(node[i], counts) if node[i].is_a?(Array); i += 1; end
end

# dynamic-modification names (see target-resolution note above for the per-class refinement)
#  [:alias, new, old] -> new ;  [:undef, name...] ;  define_method/undef_method/remove_method CALLS
#  (a literal-symbol define_method(:x){} is already lowered to [:defm] by transform, so a surviving
#   define_method CALL always has a dynamic name).
```
NB self-hosted gotcha: `h[k] ||= v` returns nil self-hosted — use explicit `h[k] = {} if !h[k]`.

## Step-by-step plan (each step: gate + sweep before commit; leave clean/documented at every pause)

1. **Direct-def + target-resolved dynamic analysis** → compute a per-(class,method) `devirt_ok?`
   predicate for the literal classes only. Validate with `DEVIRT_ANALYZE`-style logging against the
   census numbers above. (No codegen change; commit only with a consumer to avoid dead code, so pair
   with step 2.)
2. **Wire the conservative direct call** in compile_calls.rb: when `ob` is a typed literal of class C and
   `devirt_ok?(C, m)`, emit `@e.call("__method_#{C}_#{clean_method_name(m)}")` instead of `@e.callm(m)`.
   Keep everything else identical. Gate + FULL SWEEP (crash set must stay == baseline) before commit.
3. **Measure** the emitted-code win on a devirt-friendly benchmark (typed-literal-heavy) and on
   self-compile. Expect modest self-compile (few literal receivers there); the point is proving the
   generic machinery + correctness.
4. **Drop the dead `load_class`** before an eligible direct call (peephole/skip) once step 2 is proven.
5. **FLOW receiver-class inference (the big prize):** infer exact classes of variable/result receivers
   (generalize Phase 1 from "non-fixnum" to a class lattice), unlocking devirt for the 82% of receivers
   that are variables — and enabling arithmetic inlining (fixnum `a+b` → raw add + overflow→bignum slow
   path when a,b provably Integer and Integer#+ stable). Large; do after 1-4 prove the resolution+emission
   pipeline.

## BLOCKER found (2026-07-13): soundness needs receiver/escape reasoning, not local heuristics

Attempted the v1 analysis and hit a wall. To prove `<literal C>.m` is safe to direct-call, we must prove
no runtime metaprogramming redefines `C#m`. lib/core's own metaprogramming (`Class.new(...).class_eval
(&block)`, `(class << self).send(:define_method, ...)`) is harmless to the literal classes ONLY because
its receiver is a fresh anonymous class / a singleton — but that receiver arrives through a LOCAL
VARIABLE (`klass`, `sc`). Classifying it therefore requires reasoning about what those locals hold, i.e.
per-local value/reaching-definitions analysis. User ruled that out (2026-07-13: "you can't determine
anything from the names of locals") — and it is genuinely fragile (the attempt double-tainted everything
anyway). Consequence: with lib/core always included, a conservative analysis marks ALL literal classes
"possibly modified" and devirt fires nowhere; a non-conservative one is unsound.

**Implication:** typed-literal devirt is NOT a cheap first slice. Sound devirtualization of instance
dispatch requires either (a) a proper whole-program FLOW type + ESCAPE analysis (infer every receiver's
class AND prove the class object never escapes to a metaprogramming site — large, but it is the real
"type inference" the project wants, and it subsumes receiver typing for variables too), or (b) making
lib/core's reflective metaprogramming statically transparent (e.g. so `Class.new(...).class_eval` is
recognizable without an intermediary local), or (c) a different optimization target. Awaiting steer on
which. Do NOT ship a local-name/receiver-pattern heuristic.

## CHOSEN DIRECTION (2026-07-13, user): devirtualize calls to FROZEN classes

Soundness from immutability instead of a "prove nothing modifies it" analysis. A frozen class cannot be
modified (modification raises FrozenError), so its method table is fixed == the compile-time definitions.
Then devirt of `<recv-of-frozen-class-C>.m` to `__method_C_<m>` is sound. Generic + opt-in: ANY code can
freeze its own classes to enable this; the compiler additionally freezes key system classes early. This
is the near-term path; long-term whole-program flow inference (below) still wanted, and this opens the
road to it (the "receiver is class C" half is shared).

Rule (user): "devirtualize all calls that can be PROVEN — by static analysis or by guards — to belong to
any FROZEN class. The compiler can freeze key system classes early. All calls that can be shown to not
occur until after those freeze calls can be safely devirtualized."

### Why this is tractable HERE (AOT insight)
This is an AOT compiler: the ONLY runtime class modification is the reflective methods (define_method /
class_eval-with-defs / alias_method / undef_method / define-family via send). A static `class Array; def
m` reopening is compiled into Array's vtable at INIT (before the freeze) — it does NOT raise, and if it
makes m multiply-defined the devirt "defined-once" check simply skips m (vtable still routes correctly).
So freezing system classes breaks only programs that do RUNTIME reflective modification of them AFTER the
freeze. Measured spec impact: 7 specs statically reopen a system class (fine — pre-freeze, handled by
defined-once), only ~1 does runtime `.class_eval/.define_method/.send` on one.

### Prerequisite: ENFORCED class-object freezing (not yet present)
Current state: `Object#freeze` is a no-op (object.rb:268); `Class#define_method`/`class_eval` (class.rb
:465/:550) don't check frozen; Array uses a local `@frozen` ivar but only for array INSTANCES
(array.rb:1870), not the class object. Needed:
1. Freezing a CLASS object records frozen state on it (reuse the `@frozen`-ivar pattern on Class, or the
   stashed slot-1 frozen bit — the object.rb FIXME says that bit "is implemented but stashed, pending a
   parser regression"; the @frozen-ivar route is more contained).
2. `define_method` / `class_eval` / `alias_method` / `undef_method` (class.rb) raise FrozenError when
   `self` (the receiver class) is frozen. NB lib/core's own runtime define_method targets FRESH classes
   (Class.new) and SINGLETONS (define_singleton_method) which are never frozen — so enforcement won't
   break Struct/Data/attr_*/define_singleton_method.

### Freeze placement + "after freeze" analysis
The compiler freezes the chosen system classes at a known point AFTER lib/core is fully defined and
BEFORE user top-level code (`__main`). USER CAUTION (2026-07-13): a call that MIGHT execute BEFORE the
freeze cannot be devirtualized — before the freeze the class can still be modified, so the compile-time
label may be stale. So devirt is allowed only at call sites that provably run AFTER the freeze. Sound
approximation via a NAME-BASED CALL-GRAPH closure (no receiver types needed, so buildable first):
  - Pre-freeze ROOTS = every method NAME invoked from code that runs during pre-freeze init = the
    top-level class/module BODY statements (they execute when the class is defined, before __main's
    post-freeze region) plus any top-level statements ordered before the freeze call.
  - PRE-FREEZE-REACHABLE method names = closure: a called name pulls in ALL methods defined with that
    name (dynamic dispatch over-approximation), whose bodies contribute the names THEY call, to fixpoint.
  - A call site may devirt only if it is NOT inside a pre-freeze-reachable method (and not itself in
    pre-freeze top-level code). Expected to be permissive because lib/core class BODIES are mostly bare
    `def`s (few top-level calls) — VERIFY the root set is small, else the closure explodes and devirt
    fires nowhere.
This also generalizes to user `C.freeze` at an arbitrary point: roots = names reachable before that
freeze in program order.

### The only analysis needed (all non-fragile, NO local reasoning)
1. Per-class DIRECT `[:defm]` counts — a plain AST scan (`depth_first(:class)` + a body scan stopping at
   nested class/module/defm). Gives the `__method_C_<m>` label and the defined-once guard. (Reuse the
   compute_class_direct_methods sketch already in this doc.)
2. The set of FROZEN classes (the ones the compiler emits freeze for; later, ones a program freezes — a
   scan for `C.freeze` with C an explicit class constant, honoring program order for the "after" part).
3. Receiver class = TYPED LITERAL for v1 (`[:array]`->Array, string->String, `[:hash]`->Hash,
   `[:float]`->Float, `[:sexp,:__S_]`->Symbol, integer literal->Integer). Later: flow inference.

### Step plan (each: gate + full sweep before commit; commit only when green)
1. Enforced class freeze: Class#freeze records frozen; define_method/class_eval/alias_method/undef_method
   raise FrozenError if frozen. Test: `C.freeze; C.define_method(:x){}` raises; fresh/singleton unaffected.
   Sweep to confirm no regression from adding the checks alone (nothing frozen yet).
2. Compiler emits freeze for the system classes post-lib/core, pre-__main. Sweep; assess the (~1) runtime-
   modification spec fallout; decide the class set.
3. Devirt consumer in compile_calls.rb: typed-literal receiver of a frozen class C, m defined-once on C ->
   emit `@e.call("__method_#{C}_#{clean_method_name(m)}")` instead of `@e.callm`. Restrict to method-body/
   __main code (post-freeze). Gate + full sweep (crash set == baseline). MEASURE self-compile.
4. Extend receiver typing beyond literals via the flow inference below.

## Open risks
- compile_callm is the hottest, most delicate codegen path — a wrong label = wrong method = crash. Keep
  v1 ultra-conservative (typed literals only, count==1, target-resolved-clean).
- The `attr_*`/dynamic-`self` define_method target resolution is the one genuinely fiddly analysis; get it
  provably sound or conservatively over-disable (safe, just forgoes some devirt).
- Don't measure via self-compile TIME when emit volume changes (confounded); measure a fixed input.
