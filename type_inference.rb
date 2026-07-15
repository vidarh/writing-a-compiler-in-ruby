# frozen_string_literal: true
#
# Whole-program, FLOW-SENSITIVE type inference (points-to on receiver classes) + generation/slot tracking.
# Inference-first; devirt is a later consumer. Verified via `--type-ast`. Runs in `compile` before codegen.
# See docs/devirt_plan.md.
#
# STATE threaded forward through control flow (forked at branches, joined at merges, fixpointed at loops):
#   st[:v]  = { var_sym => class-set }                 -- points-to for locals/params
#   st[:s]  = { class_sym => slotmap }                 -- the vtable GENERATION per class at this point
#            slotmap = TS_UNK (whole class unknowable) | { method_sym => fnset }
#            fnset   = TS_UNK (slot could hold anything) | { label => true }  ; absent key = not defined yet
#
# class-set / fnset = TS_TOP/TS_UNK (any) | Hash | nil (bottom). Sound "may": unknown -> TS_TOP/TS_UNK.
# Generations are inherently flow-sensitive: a `def` transitions a slot (the label it writes = "what
# changes"); a CALL conservatively invalidates the slots it might reach (-> a generation boundary) until
# interprocedural modification summaries refine it; a dynamic-name/target `define_method` collapses the
# affected class (or all) to unknowable -- the pathological case that must stay sound (devirt just bails).

class TypeInference
  TS_TOP = :__top     # any class (points-to)
  TS_UNK = :__unk     # unknowable slot/generation
  TS_NIL = { :NilClass => true }

  def initialize
    @types = {}   # node.object_id -> class-set at its eval point
    @gen   = {}   # node.object_id -> a short generation note (for the dump)
    @cnt_eval = 0
    @cnt_eval_node = 0
    @cnt_join = 0
    @cnt_join_equal = 0
    @cnt_join_subset_ab = 0
    @cnt_join_subset_ba = 0
    @cnt_join_new = 0
    @cnt_join_size1 = 0
    @cnt_join_size2 = 0
    @cnt_join_size3plus = 0
    @cnt_ts_eq = 0
    @cnt_merge = 0
    @cnt_interproc_call = 0
    @cnt_callees = 0
  end
  attr_reader :types, :gen

  # Lightweight phase timer. Output is off unless COMPILER_TIME=1.
  def time_phase(name)
    return yield unless ENV["COMPILER_TIME"]
    t0 = Time.now
    yield
    t1 = Time.now
    STDERR.puts "[time] ti.#{name}: %.3fs" % (t1 - t0)
  end

  # ---- class-set / fnset lattice ----
  def join(a, b)
    @cnt_join += 1
    return TS_TOP if a == TS_TOP || b == TS_TOP
    return b if a.nil?
    return a if b.nil?
    if a.equal?(b)
      @cnt_join_equal += 1
      return a
    end
    # Check subset relationships to avoid creating a new hash
    alen = a.length
    blen = b.length
    if alen <= blen && a.each_key.all? { |k| b.key?(k) }
      @cnt_join_subset_ab += 1
      return b
    end
    if blen <= alen && b.each_key.all? { |k| a.key?(k) }
      @cnt_join_subset_ba += 1
      return a
    end
    @cnt_join_new += 1
    alen = a.length
    blen = b.length
    @cnt_join_size1 += 1 if alen == 1 || blen == 1
    @cnt_join_size2 += 1 if alen == 2 || blen == 2
    @cnt_join_size3plus += 1 if alen > 2 || blen > 2
    o = {}; a.each { |k, _| o[k] = true }; b.each { |k, _| o[k] = true }; o
  end
  def ts_eq(a, b)
    @cnt_ts_eq += 1
    return true if a.equal?(b)
    return false if a == TS_TOP || b == TS_TOP || a.nil? || b.nil?
    return false if a.length != b.length
    a.each_key { |k| return false if !b[k] }; true
  end
  def ts_str(ts)
    return "TOP" if ts == TS_TOP
    return "UNK" if ts == TS_UNK
    return "BOT" if ts.nil? || (ts.respond_to?(:empty?) && ts.empty?)
    "{" + ts.keys.map(&:to_s).sort.join(",") + "}"
  end

  # ---- state ----
  def st0; { :v => {}, :s => {} }; end
  def dupst(st); { :v => st[:v].dup, :s => st[:s].dup }; end

  # merge two states: per-var join (missing => NilClass, Ruby); per-class slotmap merge
  def merge(a, b)
    @cnt_merge += 1
    v = {}
    ks = {}; a[:v].each_key { |k| ks[k] = true }; b[:v].each_key { |k| ks[k] = true }
    ks.each_key { |k| v[k] = join(a[:v].key?(k) ? a[:v][k] : TS_NIL, b[:v].key?(k) ? b[:v][k] : TS_NIL) }
    s = {}
    cs = {}; a[:s].each_key { |k| cs[k] = true }; b[:s].each_key { |k| cs[k] = true }
    cs.each_key { |c| s[c] = merge_slotmap(a[:s][c], b[:s][c]) }
    { :v => v, :s => s }
  end
  def merge_slotmap(a, b)
    return TS_UNK if a == TS_UNK || b == TS_UNK
    a ||= {}; b ||= {}
    o = {}
    ms = {}; a.each_key { |m| ms[m] = true }; b.each_key { |m| ms[m] = true }
    ms.each_key do |m|
      av = a[m]; bv = b[m]
      # a slot defined on one path but not the other -> could be undefined -> unknowable (miss vs fn)
      o[m] = (av.nil? || bv.nil?) ? TS_UNK : join_fn(av, bv)
    end
    o
  end
  def join_fn(a, b); (a == TS_UNK || b == TS_UNK) ? TS_UNK : join(a, b); end

  def state_eq(a, b)
    return false if a[:v].length != b[:v].length || a[:s].length != b[:s].length
    a[:v].each { |k, x| return false if !b[:v].key?(k) || !ts_eq(x, b[:v][k]) }
    a[:s].each { |c, sm| return false if !slotmap_eq(sm, b[:s][c]) }
    true
  end
  def slotmap_eq(a, b)
    return a == b if a == TS_UNK || b == TS_UNK
    a ||= {}; b ||= {}
    return false if a.length != b.length
    a.each { |m, x| return false if !b.key?(m) || !fn_eq(x, b[m]) }; true
  end
  def fn_eq(a, b); (a == TS_UNK || b == TS_UNK) ? a == b : ts_eq(a, b); end

  # query the current function-set in slot (C,m): TS_UNK if unknowable, nil if not defined yet, else fnset
  def slot(st, c, m)
    sm = st[:s][c]
    return TS_UNK if sm == TS_UNK
    sm ? sm[m] : nil
  end
  def set_one(st, c, m, fnset)   # low-level: set slot (c,m) in an already-duped st[:s]
    sm = st[:s][c]
    if sm == TS_UNK
      sm = { m => fnset }        # class already unknowable; a known def re-pins this one slot
    else
      sm = (sm || {}).dup
      sm[m] = fnset
    end
    st[:s][c] = sm
  end
  # Setting slot (C,m) also PROPAGATES to every descendant of C that was still inheriting C's old m --
  # mirroring __set_vtable's down-propagation into non-overriding children. This is a SOUNDNESS
  # requirement: without it a subclass slot would look stable across a superclass `def` and be wrongly
  # devirtualized. A descendant that overrode m (its slot != C's old value) keeps its own.
  def set_slot(st, c, m, fnset)
    old = slot(st, c, m)
    st[:s] = st[:s].dup
    set_one(st, c, m, fnset)
    (@descendants[c] || []).each do |d|
      set_one(st, d, m, fnset) if fn_inherits?(slot(st, d, m), old)
    end
  end
  def make_class_unknowable(st, c)
    st[:s] = st[:s].dup
    st[:s][c] = TS_UNK
  end
  # A call is EVALUATED for its effect via a modification summary, NOT blanket-invalidated. A call to a
  # name that provably modifies no vtable (transitively) leaves the slot state untouched. Only a call whose
  # target could modify a vtable (a modifier, or an unknown/dynamic target) invalidates -- and, until
  # per-(class,method) summaries land, it conservatively invalidates every known slot. `@unsafe[name]` =
  # this name's methods could (transitively) modify a vtable, or the name is unknown/dynamic.
  def call_effect(st, name)
    return st if name.is_a?(Symbol) && @safe && @safe[name]   # provably modifies nothing -> no boundary
    invalidate_all(dupst(st))
  end
  def invalidate_all(st)
    ns = {}
    st[:s].each do |c, sm|
      ns[c] = (sm == TS_UNK) ? TS_UNK : (h = {}; sm.each { |m, _| h[m] = TS_UNK }; h)
    end
    st[:s] = ns
    st
  end

  # ---- modification-summary pre-pass (name-based, sound over-approximation of the call graph) ----
  # @safe[name] = true iff every method of `name` is DEFINED and neither directly modifies a vtable
  # (a def/alias/undef in its body) nor (transitively) calls a name that is not safe. Greatest fixpoint:
  # start every DEFINED name safe, remove any with a direct modification or that calls a non-safe/unknown
  # name, iterate. Unknown names (no def) are never safe (could be method_missing / anything).
  def compute_safe(prog)
    defined = {}   # name -> [body,...]
    collect_defs(prog, defined)
    direct = {}    # name -> true if a body directly modifies a vtable
    calls  = {}    # name -> {called-name => true}
    defined.each do |name, bodies|
      cs = {}
      dm = false
      bodies.each do |b|
        dm = true if body_directly_modifies?(b)
        collect_calls(b, cs)
      end
      direct[name] = dm
      calls[name] = cs
    end
    safe = {}
    defined.each { |name, _| safe[name] = !direct[name] }
    changed = true
    while changed
      changed = false
      defined.each do |name, _|
        next if !safe[name]
        calls[name].each_key do |cn|
          if !defined.key?(cn) || !safe[cn]   # calls an unknown or non-safe name
            safe[name] = false; changed = true; break
          end
        end
      end
    end
    safe
  end

  def collect_defs(node, out, in_body = false)
    return if !node.is_a?(Array)
    t = node[0]
    if t == :defm && node[1].is_a?(Symbol)
      # NB explicit init, not `(h[k] ||= []) << v`: the op-assign-index form returns nil self-hosted.
      out[node[1]] = [] if !out[node[1]]
      out[node[1]] << node            # record the whole defm; body scanned via its subtree
    end
    node.each { |c| collect_defs(c, out, in_body) if c.is_a?(Array) }
  end
  # a def/alias/undef anywhere inside a method body is a RUNTIME vtable modification.
  # NB: the parameter must NOT be named `defm` -- a param name equal to a node tag makes the method's args
  # list the node [:defm], which depth_first(:defm) then mis-visits as a malformed def (nil name). See the
  # node-tag/local-name collision class in the compiler.
  def body_directly_modifies?(dm_node)
    found = false
    argi = 2
    i = argi + 1
    while i < dm_node.length
      found ||= subtree_modifies?(dm_node[i])
      i += 1
    end
    found
  end
  def subtree_modifies?(node)
    return false if !node.is_a?(Array)
    return true if node[0] == :defm || node[0] == :alias || node[0] == :undef
    return true if (node[0] == :call || node[0] == :callm) &&
                   (node[1] == :define_method || node[2] == :define_method ||
                    node[1] == :alias_method || node[2] == :alias_method)
    node.any? { |c| subtree_modifies?(c) }
  end
  def collect_calls(node, out)
    return if !node.is_a?(Array)
    t = node[0]
    return if t == :defm || t == :defun    # nested scope: its calls are attributed to it, not here
    if t == :callm && node[2].is_a?(Symbol) then out[node[2]] = true
    elsif t == :call && node[1].is_a?(Symbol) then out[node[1]] = true
    end
    node.each { |c| collect_calls(c, out) if c.is_a?(Array) }
  end

  # ---- reflection / generations: which SLOTS a class's generation may advance beyond a single static def ----
  # A reflective helper (attr_reader/writer/accessor, define_method, ...) advances a SPECIFIC slot's
  # generation. Rather than deciphering that from the helper's s-expressions, each core helper carries a
  # `%s(__compiler_internal type_effect ...)` pragma (compile_pragma.rb) declaring its net effect; @effects
  # maps the helper's NAME to that declaration. compute_slots then resolves a class-body call to the helper
  # against the call's literal arg to mark exactly the affected slot @dyn_slot -- leaving the class's OTHER
  # slots (ordinary `def`s) provably single-generation and devirtualizable. An un-annotated method that
  # transitively calls define_method (a user-defined definer) has no pragma, so its target slot is unknown ->
  # the whole class is marked @unknowable (the sound fallback). This replaces the old whole-class @dyn_defined.
  def compute_effects(prog)
    @effects = {}          # helper NAME => [[kind, arg-index], ...]
    effects_walk(prog)
  end
  # An effect pragma sits as a body statement `[:sexp, [:__compiler_internal, :type_effect, kind, argi]]`.
  def effects_walk(node, cur = nil)
    return if !node.is_a?(Array)
    if node[0] == :defm && node[1].is_a?(Symbol)
      cur = node[1]
    elsif node[0] == :sexp && node[1].is_a?(Array) && node[1][0] == :__compiler_internal &&
          node[1][1] == :type_effect && cur
      e = node[1]
      @effects[cur] = [] if !@effects[cur]     # explicit init (op-assign-index returns nil self-hosted)
      @effects[cur] << [e[2], e[3]]            # [kind, arg-index]
    end
    node.each { |c| effects_walk(c, cur) if c.is_a?(Array) }
  end
  # Method NAMEs that, when called (with class self), (transitively) run a define_method. attr_reader is a
  # base definer; attr_accessor calls attr_reader/attr_writer so the fixpoint pulls it in.
  def compute_definers(prog)
    defs = {}; collect_defs(prog, defs)
    calls = {}          # name -> {called-name => true} (collect_calls over the body STATEMENTS)
    defs.each do |name, bodies|
      cs = {}
      bodies.each do |b|
        # collect_calls returns immediately on a :defm node, so pass the body statements (index 3+), not
        # the whole defm. Reusing collect_calls (proven self-host-safe) also avoids a bespoke deep tree
        # traversal, which segfaulted the self-hosted compiler here.
        i = 3
        while i < b.length
          collect_calls(b[i], cs)
          i += 1
        end
      end
      calls[name] = cs
    end
    definer = {}
    names = defs.keys
    b = 0
    while b < names.length
      n = names[b]; b += 1
      definer[n] = calls[n][:define_method] ? true : false   # base: directly calls define_method
    end
    # Transitive fixpoint using .keys + while loops ONLY -- an each_key block over a POPULATED hash that
    # mutates a captured local segfaults the self-hosted compiler here (compute_safe's identical loop never
    # actually iterates because its collect_calls(defm) is a no-op, so this shape was never exercised before).
    changed = true
    while changed
      changed = false
      x = 0
      while x < names.length
        n = names[x]; x += 1
        next if definer[n]
        ck = calls[n].keys
        j = 0
        while j < ck.length
          if definer[ck[j]]
            definer[n] = true; changed = true
          end
          j += 1
        end
      end
    end
    definer
  end
  # Per-slot generation state (replaces the whole-class @dyn_defined, the per-name @unstable, and the global
  # @eigen_dynamic). ONE walk populates:
  #   @slot_defs[[C,m]] = number of STATIC class-body defs of m on C. >1 => Globals#set suffixed the label =>
  #                       the base name is not the live slot (a later generation replaced it).
  #   @dyn_slot[[C,m]]  = slot (C,m) may be (re)set at runtime or by a reflective helper on THIS class => its
  #                       generation range is not a single static label => not devirtualizable.
  #   @unknowable[C]    = C may gain an ARBITRARILY-named method (dynamic-name define_method / un-annotated
  #                       user definer whose target slot we cannot resolve) => none of C's slots are stable.
  #   @dyn_singleton[m] = m may be installed as a SINGLETON on some object (def obj.m / extend / eigenclass
  #                       define_method) => not devirtualizable on any receiver (narrow per-name open-world
  #                       residue: we cannot pin object identity).
  #   @dyn_global       = a reflective op with an unbounded target class in effective code => disable devirt.
  def compute_slots(prog)
    @slot_defs = {}
    @dyn_slot = {}
    @unknowable = {}
    @dyn_singleton = {}
    @custom_new = {}     # class => true : defines a custom class-level `new` (a factory like Struct/Data/Class
                         # whose `new` returns a CLASS/other, not an instance) -> the `C.new -> {C}` rule bails.
    @dyn_global = false
    @definer = compute_definers(prog)
    slot_walk(prog, nil, false, {})
  end
  def custom_new?(c)
    mro(c).each { |a| return true if @custom_new[a] }
    false
  end
  def set_dyn_slot(c, m); @dyn_slot[[c, m]] = true if c && m.is_a?(Symbol); end
  # A symbol-LITERAL argument ([:sexp,:__S_foo] -> :foo). Strict: a bare Symbol is a VARIABLE reference, not a
  # literal, so it returns nil (an unresolvable dynamic name) -- never mistakes `attr_reader var` for a slot.
  def sym_arg(node)
    if node.is_a?(Array) && node[0] == :sexp && node[1].is_a?(Symbol)
      s = node[1].to_s
      return s[4, s.length].to_sym if s.length > 4 && s[0, 4] == "__S_"
    end
    nil
  end
  # arg i of a :call/:callm arg node, which is either an Array of args or a single bare arg.
  def call_arg(a, i)
    return a[i] if a.is_a?(Array)
    return a if i == 0
    nil
  end
  # lex = nearest lexically-enclosing named class (default definee for `def`/`alias`), nil if none.
  # in_rt = inside a method/block body -> self is not a class object, and a `def` here modifies at runtime.
  # eigen = locals in this body bound to an eigenclass (`v = class << x; self; end`).
  def slot_walk(node, lex, in_rt, eigen)
    return if !node.is_a?(Array)
    t = node[0]
    if t == :class || t == :module
      if node[1].is_a?(Symbol)
        slot_walk(node[2], lex, in_rt, eigen) if t == :class && node[2].is_a?(Array)   # superclass expr
        node[3].each { |s| slot_walk(s, node[1], false, {}) } if node[3].is_a?(Array)   # body: self=this class
      else                                              # `class << recv` -- defs here install singletons
        node[3].each { |s| slot_walk(s, nil, true, eigen) } if node[3].is_a?(Array)
      end
      return
    end
    if t == :defm
      slot_def(node, lex, in_rt)
      ev = {}; collect_eigen_vars(node, ev)
      i = 2
      while i < node.length; slot_walk(node[i], lex, true, ev); i += 1; end   # body runs at call time
      return
    end
    if t == :defun
      ev = {}; collect_eigen_vars(node, ev)
      i = 1
      while i < node.length; slot_walk(node[i], lex, true, ev); i += 1; end   # block/lambda body: runtime
      return
    end
    if t == :call && node[1].is_a?(Symbol)
      reflect_call(node[1], node[2], (in_rt ? nil : lex), in_rt, nil, eigen)   # implicit self = lex in a body
    elsif t == :callm && node[2].is_a?(Symbol)
      reflect_callm(node, lex, in_rt, eigen)
    elsif t == :alias
      set_dyn_slot(lex, node[1]) if node[1].is_a?(Symbol)     # alias (re)sets the new name's slot
    elsif t == :undef
      j = 1
      while j < node.length; set_dyn_slot(lex, node[j]); j += 1; end
    end
    node.each { |c| slot_walk(c, lex, in_rt, eigen) if c.is_a?(Array) }
  end
  def slot_def(node, lex, in_rt)
    m = node[1]
    if m.is_a?(Symbol)
      if in_rt
        # A runtime `def` (inside a method/block body). Its default definee is not statically reliable -- a
        # block may be class_eval'd onto another class -- so bail m globally (the old @unstable semantics)
        # rather than risk an unsound per-slot attribution to the lexical class.
        @dyn_singleton[m] = true
      elsif lex
        @slot_defs[[lex, m]] = (@slot_defs[[lex, m]] || 0) + 1                  # static class-body def
      else
        @dyn_singleton[m] = true                                              # top-level/unknown-target def
      end
    elsif m.is_a?(Array) && m[1].is_a?(Symbol)                                # singleton `def recv.m`
      r = m[0]
      if !in_rt && (r == :self || (r.is_a?(Symbol) && ti_const?(r)))
        # class-body `def self.m` / `def Const.m` is a CLASS method (on the class object's eigenclass); it
        # does not affect instance-method dispatch. But record a custom `new` so the `C.new -> {C}`
        # allocation rule bails (a factory `new` returns a CLASS/other, not an instance of C).
        tc = (r == :self) ? lex : r
        @custom_new[tc] = true if m[1] == :new && tc
      else
        @dyn_singleton[m[1]] = true                                          # singleton on some object
      end
    end
  end
  def reflect_callm(node, lex, in_rt, eigen)
    m = node[2]; r = node[1]; args = node[3]
    if m == :send || m == :__send__                     # recv.send(:name, ...) -- reflective form
      nm = args.is_a?(Array) ? sym_arg(args[0]) : sym_arg(args)
      return if nm.nil?
      rest = args.is_a?(Array) ? args[1, args.length] : nil   # drop the leading name -> indices line up
      reflect_call(nm, rest, callm_target(r, lex, in_rt), in_rt, r, eigen)
      return
    end
    return mark_extend(args) if m == :extend
    reflect_call(m, args, callm_target(r, lex, in_rt), in_rt, r, eigen)
  end
  # The class an explicit receiver denotes when statically pinnable to a concrete class body: `self` in a
  # class body -> that class; a constant -> that constant. Otherwise nil (unknown / eigen / instance).
  def callm_target(r, lex, in_rt)
    return nil if in_rt
    return lex if r == :self
    return r if r.is_a?(Symbol) && ti_const?(r)
    nil
  end
  def reflect_call(name, args, tclass, in_rt, recv, eigen)
    return if name.nil?
    return apply_singleton_define(args) if name == :define_singleton_method
    # define_method on an eigenclass-bound var (`v = class << x; self; end`) installs a SINGLETON on some
    # object x -> the eigenclass open-world domain, which does not affect named-class instance-method
    # dispatch here. Skip (matches the pre-generation analysis; documented residual hole).
    return if recv.is_a?(Symbol) && eigen && eigen[recv]
    return apply_pragma_effect(name, args, tclass) if @effects[name]
    if name == :define_method || (name.is_a?(Symbol) && @definer[name])   # define_method / un-annotated definer
      if tclass then @unknowable[tclass] = true          # can't resolve the slot -> any of tclass's may change
      elsif !in_rt then @dyn_global = true end            # unbounded target class in effective code
      # in_rt with no tclass: a definer forwarding inside a method body -- its net effect is recorded at the
      # concrete-class use site, nothing to add here.
    end
  end
  def apply_pragma_effect(name, args, tclass)
    return if tclass.nil?                                 # helper not invoked with a concrete class self
    effs = @effects[name]
    i = 0
    while i < effs.length
      e = effs[i]; i += 1
      sv = sym_arg(call_arg(args, e[1]))
      if sv.nil? then @unknowable[tclass] = true          # dynamic slot name -> any of tclass's slots
      elsif e[0] == :defines_slot then set_dyn_slot(tclass, sv)
      elsif e[0] == :defines_slot_eq then set_dyn_slot(tclass, (sv.to_s + "=").to_sym)
      end
    end
  end
  def apply_singleton_define(args)
    nm = sym_arg(call_arg(args, 0))
    if nm then @dyn_singleton[nm] = true else @dyn_global = true end
  end
  # `recv.extend(Mod)` installs Mod's (and its ancestors') instance methods as singletons on recv -> those
  # names become eigenclass overrides on some object -> not devirtualizable. Literal module const: mark those
  # names @dyn_singleton. Dynamic module expr: unbounded -> @dyn_global.
  def mark_extend(args)
    return (@dyn_global = true) if !args.is_a?(Array)
    args.each do |a|
      if a.is_a?(Symbol) && ti_const?(a)
        mro(a).each { |c| @methods.each_key { |k| @dyn_singleton[k[1]] = true if k[0] == c } }
      elsif a.is_a?(Array)
        @dyn_global = true
      end
    end
  end
  def collect_eigen_vars(node, out)
    return if !node.is_a?(Array)
    if node[0] == :assign && node[1].is_a?(Symbol) && node[2].is_a?(Array) &&
       node[2][0] == :class && node[2][1].is_a?(Array) && node[2][1][0] == :eigen
      out[node[1]] = true
    end
    node.each { |c| collect_eigen_vars(c, out) if c.is_a?(Array) }
  end
  # ---- eval: [type-set, state] ----
  def eval(node, st)
    @cnt_eval += 1
    return [TS_NIL, st] if node == :nil
    return [{ :TrueClass => true }, st]  if node == :true
    return [{ :FalseClass => true }, st] if node == :false
    if node.is_a?(Symbol)
      # a bare lowercase non-local symbol in expr position is a self-send (possible_callm) -> a CALL
      if st[:v].key?(node)
        return [st[:v][node], st]
      elsif ti_const?(node)
        return [TS_TOP, st]                          # constant reference
      else
        self_ty = st[:v][:self] || TS_TOP
        return [interproc_call(self_ty, node, []), call_effect(st, node)]
      end
    end
    return [TS_TOP, st] if !node.is_a?(Array)
    # A node whose head is NOT a Symbol is a bare STATEMENT LIST (e.g. a when-body [[:assign,...],...], or a
    # class/case body slice), not a tagged node. Evaluate every element from index 0 -- otherwise eval_node's
    # default treats element 0 as a tag and eval_kids(node,1) DROPS the first statement, so its assignments
    # are never seen and the vars it writes are under-approximated (e.g. `first = @s.get` in a case -> first
    # stays {NilClass} -> `first == x` mis-devirtualized to NilClass#==).
    if !node[0].is_a?(Symbol)
      return eval_seq(node, 0, st)
    end
    ty, st = eval_node(node, node[0], st)
    @types[node.object_id] = ty
    [ty, st]
  end

  def eval_node(node, t, st)
    @cnt_eval_node += 1
    case t
    when :array then [{ :Array => true }, eval_kids(node, 1, st)]
    when :hash  then [{ :Hash => true },  eval_kids(node, 1, st)]
    when :float then [{ :Float => true }, st]
    when :sexp
      inner = node[1]
      if inner.is_a?(Array) && inner[0] == :call && inner[1] == :__get_string then [{ :String => true }, st]
      elsif inner.is_a?(Symbol) && inner.to_s.start_with?("__FSL") then [{ :String => true }, st]
      elsif inner.is_a?(Symbol) && inner.to_s.start_with?("__S_") then [{ :Symbol => true }, st]
      elsif inner.is_a?(Integer) then [{ :Integer => true }, st]
      else [TS_TOP, taint_sexp(node, st)]
      end
    when :assign
      tv, st = eval(node[2], st)
      if node[1].is_a?(Symbol)
        st = dupst(st); st[:v][node[1]] = tv
      else
        _, st = eval(node[1], st)
      end
      [tv, st]
    when :do    then eval_seq(node, 1, st)
    when :if, :unless   # same [cond, then, else] shape; branch-join is symmetric so unless == if here
      _, s1 = eval(node[1], st)
      tt, sa = eval_arm(node[2], s1)
      tf, sb = eval_arm(node[3], s1)
      [join(tt, tf), merge(sa, sb)]
    when :ternif
      _, s1 = eval(node[1], st)
      alt = node[2]
      if alt.is_a?(Array) && alt[0] == :ternalt
        tt, sa = eval_arm(alt[1], s1); tf, sb = eval_arm(alt[2], s1)
        [join(tt, tf), merge(sa, sb)]
      else eval_arm(alt, s1) end
    when :while, :until then eval_loop(node, st)
    when :callm
      recv_ty, st = node[1] ? eval(node[1], st) : [(st[:v][:self] || TS_TOP), st]
      @recv_type[node.object_id] = recv_ty          # for the devirt-decision annotation in the dump
      argtypes, st = eval_args(node[3], st)
      widen_all_params_of(recv_ty) if node[2] == :send || node[2] == :__send__   # dynamic dispatch
      if node[2] == :new && node[1].is_a?(Symbol) && ti_const?(node[1]) && !custom_new?(node[1])
        ty = { node[1] => true }                     # C.new -> an instance of C (default allocator only)
        # C.new(args) invokes C#initialize(args): flow the args into initialize's params, else every
        # .new-argument param is under-approximated (an optional one collapses to its nil default) -> a
        # later `!param` / `param.nil?` mis-devirtualizes. Discard the return (initialize's value is unused).
        interproc_call(ty, :initialize, argtypes)
      else
        ty = interproc_call(recv_ty, node[2], argtypes)
      end
      st = call_effect(st, node[2])                  # generation effect per its summary
      [ty, st]
    when :call
      argtypes, st = eval_args(node[2], st)
      self_ty = st[:v][:self] || TS_TOP
      ty = interproc_call(self_ty, node[1], argtypes)
      st = call_effect(st, node[1])
      [ty, st]
    when :return
      rt, st = node[1] ? eval(node[1], st) : [TS_NIL, st]
      @cur_returns = join(@cur_returns, rt)
      [rt, st]
    when :and, :or
      # Short-circuit: node[2] may not run. Result = join of both operands; state merges "b ran" (sb) with
      # "b skipped" (sa) -- else an assignment inside the RHS is threaded as if it always executes.
      ta, sa = eval(node[1], st)
      tb, sb = eval(node[2], sa)
      [join(ta, tb), merge(sa, sb)]
    when :or_assign, :and_assign
      # `v ||= x` / `v &&= x`: v keeps its old value OR takes x -> new type = join(old v, type(x)).
      tr, st = eval(node[2], st)
      lhs = node[1]
      if lhs.is_a?(Symbol)
        old = st[:v].key?(lhs) ? st[:v][lhs] : TS_NIL
        st = dupst(st); st[:v][lhs] = join(old, tr)
        [st[:v][lhs], st]
      else
        [TS_TOP, st]                               # ivar/index target -- not a tracked local
      end
    when :block then eval_block(node, st)
    when :case  then eval_case(node, st)
    when :defm  then eval_defm(node, st)
    when :defun then analyze_body(node, 1, nil, nil); [{ :Proc => true }, st]
    when :class, :module then eval_classbody(node, t, st)
    else [TS_TOP, eval_kids(node, 1, st)]
    end
  end

  # [:case, subject, [[:when, cond, body], ...], else-body?]. Each when body is an ALTERNATIVE evaluated from
  # the pre-case state; the result joins all branch values (+ nil / the else) and the state merges all
  # branches (+ the no-match fall-through). Linear eval would both drop the no-match path AND thread one
  # branch's assignments into the next -> unsound either way.
  # [:block, args, body, (:rescue handler conds)..., (:ensure ...)]. A begin/rescue: an exception can raise
  # ANYWHERE in the body, so a rescue handler is evaluated from merge(pre-body, post-body) -- covering both
  # "nothing ran" and "body completed" -- and the block's result state merges the completed-body state with
  # every handler's. Without this, a var assigned late in the body looks unconditionally set (drops the
  # raised-early path).
  def eval_block(node, st)
    st = eval(node[1], st)[1] if node[1].is_a?(Array) && !node[1].empty?   # args (usually empty)
    pre = st
    bval, sb = node[2] ? eval(node[2], st) : [TS_NIL, st]
    result = bval
    merged = sb
    i = 3
    while i < node.length
      r = node[i]
      if r.is_a?(Array) && r[0] == :rescue
        hstate = merge(pre, sb)
        hval, hs = r[1] ? eval(r[1], hstate) : [TS_NIL, hstate]
        result = join(result, hval)
        merged = merge(merged, hs)
      elsif r.is_a?(Array) || r.is_a?(Symbol)
        _, merged = eval(r, merged)               # ensure / other trailing clause -- always runs
      end
      i += 1
    end
    [result, merged]
  end
  def eval_case(node, st)
    _, st = eval(node[1], st) if node[1] && (node[1].is_a?(Array) || node[1].is_a?(Symbol))
    pre = st
    result = nil
    merged = nil
    whens = node[2]
    if whens.is_a?(Array)
      whens.each do |w|
        next unless w.is_a?(Array) && w[0] == :when
        cst = pre
        _, cst = eval(w[1], cst) if w[1].is_a?(Array) || w[1].is_a?(Symbol)   # conditions (side effects/state)
        bval = TS_NIL; bst = cst
        i = 2
        while i < w.length
          bval, bst = eval(w[i], bst) if w[i].is_a?(Array) || w[i].is_a?(Symbol)
          i += 1
        end
        result = join(result, bval)
        merged = merged ? merge(merged, bst) : bst
      end
    end
    if node[3]                                     # explicit else
      ev, es = eval(node[3], pre)
      result = join(result, ev); merged = merged ? merge(merged, es) : es
    else                                           # no else: a no-match leaves state=pre, value nil
      result = join(result, TS_NIL); merged = merged ? merge(merged, pre) : pre
    end
    [result.nil? ? TS_NIL : result, merged || pre]
  end

  # a class/module-body `def m`: static def -> set slot (C,m) = {__method_C_m}. Dynamic-name def would come
  # as a define_method call, not a :defm; a :defm always has a literal name here.
  def eval_defm(node, st)
    m = node[1]
    if m.is_a?(Symbol) && @cur_class
      st = dupst(st)
      set_slot(st, @cur_class, m, { "__method_#{@cur_class}_#{ti_clean(m)}" => true })
      @gen[node.object_id] = "def #{@cur_class}##{m} -> #{ts_str(st[:s][@cur_class][m])}"
    end
    analyze_body(node, 2, @cur_class, m)   # the method body is a separate scope
    [m.is_a?(Symbol) ? { :Symbol => true } : TS_TOP, st]
  end

  def eval_classbody(node, t, st)
    prev = @cur_class
    @cur_class = node[1].is_a?(Symbol) ? node[1] : nil
    st = eval(node[2], st)[1] if t == :class && node[2].is_a?(Array)   # superclass expr, outer scope
    body = node[3]                                          # class & module both: body at node[3]
    # body is a plain STATEMENT LIST (not a tagged node): evaluate each element in order.
    if body.is_a?(Array)
      body.each { |s| _, st = eval(s, st) if s.is_a?(Array) || s.is_a?(Symbol) }
    end
    if @cur_class
      @gen[node.object_id] = "final #{@cur_class}: #{slotmap_str(st[:s][@cur_class])}"
    end
    @cur_class = prev
    [TS_NIL, st]
  end

  def slotmap_str(sm)
    return "UNK" if sm == TS_UNK
    return "{}" if sm.nil?
    "{" + sm.keys.sort.map { |m| "#{m}=>#{ts_str(sm[m])}" }.join(", ") + "}"
  end

  def eval_kids(node, i, st)
    while i < node.length
      st = eval(node[i], st)[1] if node[i].is_a?(Array) || node[i].is_a?(Symbol)
      i += 1
    end
    st
  end
  def eval_seq(node, i, st)
    last = TS_NIL
    while i < node.length
      c = node[i]
      last, st = eval(c, st) if c.is_a?(Array) || c.is_a?(Symbol)
      i += 1
    end
    [last, st]
  end
  def eval_arm(arm, st); arm.nil? ? [TS_NIL, st] : eval(arm, st); end
  def eval_loop(node, st)
    _, st = eval(node[1], st) if node[1].is_a?(Array) || node[1].is_a?(Symbol)
    cur = st; guard = 0
    while guard < 50
      guard += 1
      _, after = eval_arm(node[2], cur)
      m = merge(cur, after)
      break if state_eq(m, cur)
      cur = m
    end
    [TS_NIL, cur]
  end
  def taint_sexp(node, st)
    st = dupst(st); walk_taint(node, st); st
  end
  def walk_taint(node, st)
    return if !node.is_a?(Array)
    st[:v][node[1]] = TS_TOP if node[0] == :assign && node[1].is_a?(Symbol)
    node.each { |c| walk_taint(c, st) if c.is_a?(Array) }
  end
  def ti_const?(sym); s = sym.to_s; s.length > 0 && (b = s.getbyte(0)) >= 65 && b <= 90; end
  def ti_clean(m); m.to_s; end   # NB: real compiler uses clean_method_name; adequate for the dump

  # self inside a method of C is not just C: the method can be INHERITED, so at runtime self may be any
  # descendant of C. Typing self as {C} + descendants keeps self-send devirt sound -- a self-send to a
  # method some subclass overrides then sees non-invariant slots and bails, instead of wrongly binding the
  # base label. (Without this, an inherited method's self-send to an overridden method miscompiles.)
  def self_type_set(cls)
    h = { cls => true }
    (@descendants[cls] || []).each { |d| h[d] = true }
    h
  end
  def analyze_body(node, argi, cls, name)
    st = st0
    # `name` is a Symbol only for a normal instance method. A SINGLETON def (`def self.m`/`def obj.m`) has an
    # Array name and is NOT in @methods, so NO call ever records its params/return -> we cannot bound its
    # arg types. Type self AND every param as TOP for those (and for blocks, cls=nil). Otherwise the params
    # default to {NilClass} (bottom seed + the default prologue) and a check on them mis-devirtualizes --
    # e.g. File.basename(name, suffix=nil)'s suffix looked {NilClass}, skipping the suffix-strip branch.
    known = cls && name.is_a?(Symbol)
    st[:v][:self] = known ? self_type_set(cls) : TS_TOP
    args = node[argi]
    if args.is_a?(Array)
      i = 0
      args.each do |a|
        # An optional param is `[:name, :default, val]`, a splat `[:name, :rest]`, etc. -- NOT a bare Symbol.
        # Seed it from @param_types (the passed-arg types) whichever form it takes; else the default-value
        # prologue (`if numargs<N; name = default`) + "missing var => NilClass" makes it look {NilClass}.
        pname = a.is_a?(Symbol) ? a : ((a.is_a?(Array) && a[0].is_a?(Symbol)) ? a[0] : nil)
        st[:v][pname] = known ? @param_types[[cls, name, i]] : TS_TOP if pname
        i += 1
      end
    end
    sc = @cur_class; sr = @cur_returns
    @cur_class = nil; @cur_returns = nil
    last, _ = eval_seq(node, argi + 1, st)
    @cur_returns = join(@cur_returns, last)        # fall-through value is a return
    grow_return([cls, name], @cur_returns) if cls && name
    @cur_class = sc; @cur_returns = sr
  end

  # ---- interprocedural: build (class,name)->defm and its class; type self/params/returns ----
  # Context-INSENSITIVE: a method's param i type = union of arg i over ALL its call sites; its return type
  # = union of its return expressions; a call `recv.m` reaches method m of every class in type(recv)
  # (self-send: recv=self, typed as the enclosing class). Mutual with points-to -> iterate to a fixpoint.
  def build_methods(prog)
    @methods = {}          # [class, name] => defm node
    @mclass  = {}          # defm.object_id => class it is defined on
    @super   = {}          # class => superclass
    @incl    = {}          # class => [included module, ...]
    @qnames  = {}          # simple const name => { fully-qualified label name => true }
    bm_walk(prog, :Object, "")
    compute_descendants
  end

  # The compiler labels a method __method_<scope.name>_<clean(m)>, where scope.name is the FULLY-QUALIFIED
  # class name (M::C -> "M__C"). The inference keys classes by simple const name, so a direct label is only
  # reconstructable when the simple name is UNIQUE and TOP-LEVEL (qualified == simple). label_safe? gates
  # devirt to exactly those classes; nested / name-colliding classes bail (sound). Covers the core-lib
  # classes (Integer/Array/String/...), which are all top-level.
  def label_safe?(c)
    q = @qnames[c]
    q && q.length == 1 && q.key?(c.to_s)
  end

  # @descendants[C] = every class that has C in its MRO (transitive subclasses + includers). A `def C#m`
  # propagates to these (mirroring __set_vtable's down-propagation) -- REQUIRED for a sound generation:
  # a superclass/module modification changes the flattened slot of every non-overriding descendant.
  def compute_descendants
    @descendants = {}
    classes = {}
    @super.each { |k, v| classes[k] = true; classes[v] = true }
    @incl.each  { |k, vs| classes[k] = true; vs.each { |v| classes[v] = true } }
    @methods.each_key { |k| classes[k[0]] = true }
    classes.each_key do |d|
      mro(d).each do |c|
        next if c == d
        @descendants[c] = [] if !@descendants[c]   # explicit init (op-assign-index returns nil self-hosted)
        @descendants[c] << d
      end
    end
  end
  # Returns the target DEFINING CLASS (a symbol) for a devirtualizable `recv.m`, or nil. The compiler turns
  # that into the actual label __method_<D>_<clean_method_name(m)> (it owns the name-mangling). This is the
  # (V,G) base case: for EVERY class V the receiver may hold, slot m must be a single static function across
  # its whole generation range. Here G is over-approximated to all generations (a slot devirts iff it is
  # defined by exactly ONE static def and never advanced by a reflective helper / runtime def on any ancestor
  # up to the resolver) -- sound; per-receiver generation ranges are a later refinement. Requires: a concrete
  # named-class set (no TOP/UNK), each class resolves through the MRO to the SAME defining class D
  # (slot-invariant across the set), D's slot m single-static-generation (@slot_defs==1, no @dyn_slot/
  # @unknowable on any nearer ancestor), m not a singleton on some object (@dyn_singleton), and D label-safe.
  def devirt_decision(recv_ts, m)
    return nil if @dyn_global                        # an unbounded reflective op -> no devirt anywhere
    return nil if !recv_ts.is_a?(Hash) || recv_ts.empty?
    return nil if @dyn_singleton[m]                  # m may be a singleton on some object -> can't pin dispatch
    target = nil
    # NB .keys + while, not recv_ts.each_key { ... target = d ... }: an each_key block over a POPULATED hash
    # that mutates a captured local segfaults the self-hosted compiler.
    cs = recv_ts.keys
    ci = 0
    while ci < cs.length
      c = cs[ci]; ci += 1
      d = resolve(c, m)
      return nil if d.nil?                           # inherited from outside the analysed set / method_missing
      # Walk c's MRO down to d: a NEARER ancestor whose slot m is dynamically modified, or which may gain
      # arbitrarily-named methods, would SHADOW d at runtime -> not devirtualizable.
      anc = mro(c)
      k = 0
      while k < anc.length
        a = anc[k]; k += 1
        return nil if @unknowable[a]
        return nil if @dyn_slot[[a, m]]
        break if a == d
      end
      return nil if @slot_defs[[d, m]] != 1          # not defined exactly once statically on d (else suffixed)
      return nil if !label_safe?(d)                  # label name not reconstructable (nested / colliding)
      return nil if target && target != d            # slot not invariant across the receiver set
      target = d
    end
    target
  end

  def fn_inherits?(dv, old)   # does descendant slot value `dv` still inherit parent's OLD value `old`?
    return old.nil? if dv.nil?
    return false if old.nil?
    fn_eq(dv, old)
  end
  def bm_walk(node, cls, prefix)
    return if !node.is_a?(Array)
    t = node[0]
    if t == :class || t == :module
      cn = node[1].is_a?(Symbol) ? node[1] : cls
      nprefix = prefix
      if node[1].is_a?(Symbol)
        q = prefix.empty? ? cn.to_s : "#{prefix}__#{cn}"
        @qnames[cn] = {} if !@qnames[cn]           # explicit init (op-assign-index returns nil self-hosted)
        @qnames[cn][q] = true                      # record this class's fully-qualified label name
        nprefix = q
      end
      if t == :class && node[2].is_a?(Symbol) && ti_const?(node[2])
        @super[cn] = node[2]                       # class C < S
      end
      body = node[3]                               # module is [:module, name, :Object, body], same as class
      if body.is_a?(Array)
        body.each do |s|
          bm_walk(s, cn, nprefix)
          record_include(cn, s)                    # include M in the class body
        end
      end
      return
    end
    if t == :defm && node[1].is_a?(Symbol)
      @methods[[cls, node[1]]] = node
      @mclass[node.object_id] = cls
      return
    end
    node.each { |c| bm_walk(c, cls, prefix) if c.is_a?(Array) }
  end
  def record_include(cls, s)
    return if !s.is_a?(Array)
    if (s[0] == :call && s[1] == :include && s[2].is_a?(Array)) ||
       (s[0] == :callm && s[2] == :include && s[3].is_a?(Array))
      args = (s[0] == :call) ? s[2] : s[3]
      args.each do |m|
        next if !m.is_a?(Symbol)
        @incl[cls] = [] if !@incl[cls]             # explicit init (op-assign-index returns nil self-hosted)
        @incl[cls] << m
      end
    end
  end

  # method-resolution order of C (C, its includes reversed, then the superclass's MRO). prepend omitted:
  # it is a no-op in this compiler. Cycle-guarded.
  def mro(c, seen = {})
    return [] if c.nil? || seen[c]
    seen[c] = true
    chain = [c]
    (@incl[c] || []).reverse_each { |m| chain.concat(mro(m, seen)) }
    s = @super[c]
    chain.concat(mro(s, seen)) if s && s != c
    chain
  end
  # the class that actually defines `name` for an instance of c (walking the MRO), or nil (inherited from
  # outside the analysed set / method_missing).
  def resolve(c, name)
    mro(c).each { |x| return x if @methods.key?([x, name]) }
    nil
  end

  # callees of a call to `name` on a receiver of type recv_ts. Returns [pairs, all_resolved?]: the resolved
  # [defining-class, name] pairs, and whether EVERY receiver class resolved (if not, the result must widen
  # to include TOP -- an unresolved class means method_missing / a definer outside the analysed set).
  def callees(recv_ts, name)
    @cnt_callees += 1
    return [:unknown, false] if recv_ts == TS_TOP || recv_ts.nil?
    out = []
    all = true
    recv_ts.each_key do |c|
      r = resolve(c, name)
      if r then out << [r, name] else all = false end
    end
    [out, all]
  end

  # evaluate an argument list, threading state; return [ [type per arg], state ]
  def eval_args(args, st)
    types = []
    if args.is_a?(Array)
      args.each do |a|
        if a.is_a?(Array) || a.is_a?(Symbol)
          ty, st = eval(a, st); types << ty
        end
      end
    elsif args.is_a?(Symbol)
      ty, st = eval(args, st); types << ty
    end
    [types, st]
  end

  # interprocedural result of calling `name` on a receiver of type recv_ty with the given arg types:
  # record args into the callees' param types, return the join of their return types. TOP if the receiver
  # is TOP or no matching (direct) method is found (inherited/method_missing not yet resolved).
  def interproc_call(recv_ty, name, argtypes)
    @cnt_interproc_call += 1
    cs, all = callees(recv_ty, name)
    if cs == :unknown
      # Unresolved receiver -> this call could reach ANY method named `name`. For SOUND param typing we must
      # widen every same-named method's params to TOP: otherwise a method whose real integer/other args only
      # ever arrive through unknown receivers (e.g. String#[](i, len) called on a TOP receiver) would keep the
      # under-approximated type from its remaining resolved/default call sites -> unsound devirt of a call on
      # that param (e.g. `len.nil?` devirt'd to NilClass#nil?). See the selftest concat-on-84 regression.
      widen_all_params_named(name, argtypes.length)
      return TS_TOP
    end
    cs.each do |c, m|
      i = 0
      argtypes.each { |at| grow_param([c, m, i], at); i += 1 }
    end
    rt = all ? nil : TS_TOP     # an unresolved receiver class -> result could be anything
    cs.each { |c, m| rt = join(rt, @return_types[[c, m]]) }
    rt
  end
  def widen_all_params_named(name, argc)
    @methods.each_key do |k|
      next if k[1] != name
      i = 0
      while i < argc
        grow_param([k[0], name, i], TS_TOP)
        i += 1
      end
    end
  end
  # `recv.send(name, *args)` / `__send__` dispatches to a method chosen at runtime -- we can't resolve which,
  # so every param of every method reachable on recv's classes could receive these args. Widen them ALL to
  # TOP (across every param position), else a method only ever called via send keeps its default-nil param
  # types and gets wrongly devirtualized (e.g. compile_* dispatched by Compiler#compile_exp's send).
  def widen_all_params_of(recv_ty)
    all = (recv_ty == TS_TOP || recv_ty.nil? || !recv_ty.is_a?(Hash))
    @methods.each do |k, dm|
      next if !all && !recv_ty.key?(k[0])
      args = dm[2]
      argc = args.is_a?(Array) ? args.length : 0
      i = 0
      while i < argc
        grow_param([k[0], k[1], i], TS_TOP)
        i += 1
      end
    end
  end

  def analyze(prog)
    @cur_class = nil
    @cur_returns = nil
    time_phase("compute_safe")   { @safe = compute_safe(prog) }
    time_phase("build_methods")  { build_methods(prog) }
    time_phase("compute_effects"){ compute_effects(prog) }
    time_phase("compute_slots")  { compute_slots(prog) }
    @param_types  = {}     # [class,name,i] => class-set
    @return_types = {}     # [class,name]   => class-set
    iter = 0
    loop do
      iter += 1
      @changed = false
      @types = {}
      @gen = {}
      @recv_type = {}
      @cur_class = :Object                        # top-level self is main, an Object
      st = st0; st[:v][:self] = { :Object => true }
      iter_t = Time.now
      eval(prog, st)
      time_phase("eval_iter_#{iter}") { } # just to print elapsed if enabled; eval already ran
      STDERR.puts "[time] ti.eval_iter_#{iter}: %.3fs" % (Time.now - iter_t) if ENV["COMPILER_TIME"]
      break if !@changed || iter > 40
    end
    STDERR.puts "[time] ti.fixpoint_iters: #{iter}" if ENV["COMPILER_TIME"]
    if ENV["COMPILER_TIME"]
      STDERR.puts "[time] ti.counters: eval=#{@cnt_eval} eval_node=#{@cnt_eval_node} join=#{@cnt_join}(eq=#{@cnt_join_equal} ab=#{@cnt_join_subset_ab} ba=#{@cnt_join_subset_ba} new=#{@cnt_join_new} sz1=#{@cnt_join_size1} sz2=#{@cnt_join_size2} sz3+=#{@cnt_join_size3plus}) ts_eq=#{@cnt_ts_eq} merge=#{@cnt_merge} interproc=#{@cnt_interproc_call} callees=#{@cnt_callees}"
    end
    self
  end

  def grow_param(key, ts)
    old = @param_types[key]
    nu = join(old, ts)
    if !ts_eq_maybe(old, nu); @param_types[key] = nu; @changed = true; end
  end
  def grow_return(key, ts)
    old = @return_types[key]
    nu = join(old, ts)
    if !ts_eq_maybe(old, nu); @return_types[key] = nu; @changed = true; end
  end
  def ts_eq_maybe(a, b)
    return true if a.equal?(b)
    return false if a.nil? != b.nil?
    ts_eq(a, b)
  end

  # Map of devirtualizable call sites -> direct-call label, keyed by the :callm node's object_id. Call AFTER
  # analyze(prog) so @recv_type holds the final receiver types. The compiler keys emission by the same node
  # objects (it runs the inference on the exact tree it then walks), so object_id identity is stable.
  # [class, name] => defm node, for the devirt-driven inliner (a devirt'd site's target body).
  def methods_map; @methods; end

  def devirt_map(prog)
    out = {}
    dv_collect(prog, out)
    # DEVIRT_MAX=N (debug): keep only the first N devirt sites in tree order, to bisect a bad site.
    if ENV["DEVIRT_MAX"]
      lim = ENV["DEVIRT_MAX"].to_i
      out = out.to_a[0, lim].to_h
    end
    out
  end
  def dv_collect(node, out, ctx = "toplevel")
    return if !node.is_a?(Array)
    ctx = "#{node[1]}" if (node[0] == :class || node[0] == :module) && node[1].is_a?(Symbol)
    ctx = "#{ctx}##{node[1]}" if node[0] == :defm && node[1].is_a?(Symbol)
    if node[0] == :callm && node[2].is_a?(Symbol)
      recv = @recv_type[node.object_id]
      d = recv ? devirt_decision(recv, node[2]) : nil
      if d
        if ENV["DEVIRT_DUMP"]
          STDERR.puts("SITE ##{out.size} in #{ctx}: #{d}##{node[2]}  recv_ts=#{ts_str(recv)}  recvnode=#{node[1].inspect[0,40]}")
        end
        out[node.object_id] = d                  # value = target defining class; compiler forms the label
      end
    end
    node.each { |c| dv_collect(c, out, ctx) if c.is_a?(Array) }
  end

  # ---- annotated dump ----
  def dump(prog, io = STDOUT); dump_node(prog, 0, io); end
  def dump_node(node, indent, io)
    pad = "  " * indent
    if !node.is_a?(Array)
      io.puts "#{pad}#{node.inspect}"; return
    end
    ann = @types[node.object_id]
    g = @gen[node.object_id]
    suffix = ann ? "   :: #{ts_str(ann)}" : ""
    suffix += "   [#{g}]" if g
    if node[0] == :callm && node[2].is_a?(Symbol)
      recv = @recv_type[node.object_id]
      d = recv ? devirt_decision(recv, node[2]) : nil
      suffix += "   >>> DEVIRT #{d}##{node[2]}" if d
    end
    io.puts "#{pad}(#{node[0].inspect}#{suffix}"
    (node[1..-1] || []).each { |c| dump_node(c, indent + 1, io) }
    io.puts "#{pad})"
  end
end
