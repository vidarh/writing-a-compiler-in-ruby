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
  end
  attr_reader :types, :gen

  # ---- class-set / fnset lattice ----
  def join(a, b)
    return TS_TOP if a == TS_TOP || b == TS_TOP
    return b if a.nil?
    return a if b.nil?
    o = {}; a.each { |k, _| o[k] = true }; b.each { |k, _| o[k] = true }; o
  end
  def ts_eq(a, b)
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
      (out[node[1]] ||= []) << node   # record the whole defm; body scanned via its subtree
    end
    node.each { |c| collect_defs(c, out, in_body) if c.is_a?(Array) }
  end
  # a def/alias/undef anywhere inside a method body is a RUNTIME vtable modification.
  def body_directly_modifies?(defm)
    found = false
    argi = 2
    i = argi + 1
    while i < defm.length
      found ||= subtree_modifies?(defm[i])
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

  # ---- eval: [type-set, state] ----
  def eval(node, st)
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
    ty, st = eval_node(node, node[0], st)
    @types[node.object_id] = ty
    [ty, st]
  end

  def eval_node(node, t, st)
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
    when :if
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
      argtypes, st = eval_args(node[3], st)
      if node[2] == :new && node[1].is_a?(Symbol) && ti_const?(node[1])
        ty = { node[1] => true }                     # C.new -> an instance of C
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
    when :defm  then eval_defm(node, st)
    when :defun then analyze_body(node, 1, nil, nil); [{ :Proc => true }, st]
    when :class, :module then eval_classbody(node, t, st)
    else [TS_TOP, eval_kids(node, 1, st)]
    end
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

  def analyze_body(node, argi, cls, name)
    st = st0
    st[:v][:self] = cls ? { cls => true } : TS_TOP
    args = node[argi]
    if args.is_a?(Array)
      i = 0
      args.each do |a|
        st[:v][a] = (cls && name) ? @param_types[[cls, name, i]] : TS_TOP if a.is_a?(Symbol)
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
    bm_walk(prog, :Object)
    compute_descendants
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
      mro(d).each { |c| (@descendants[c] ||= []) << d if c != d }
    end
  end
  def fn_inherits?(dv, old)   # does descendant slot value `dv` still inherit parent's OLD value `old`?
    return old.nil? if dv.nil?
    return false if old.nil?
    fn_eq(dv, old)
  end
  def bm_walk(node, cls)
    return if !node.is_a?(Array)
    t = node[0]
    if t == :class || t == :module
      cn = node[1].is_a?(Symbol) ? node[1] : cls
      if t == :class && node[2].is_a?(Symbol) && ti_const?(node[2])
        @super[cn] = node[2]                       # class C < S
      end
      body = node[3]                               # module is [:module, name, :Object, body], same as class
      if body.is_a?(Array)
        body.each do |s|
          bm_walk(s, cn)
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
    node.each { |c| bm_walk(c, cls) if c.is_a?(Array) }
  end
  def record_include(cls, s)
    return if !s.is_a?(Array)
    if (s[0] == :call && s[1] == :include && s[2].is_a?(Array)) ||
       (s[0] == :callm && s[2] == :include && s[3].is_a?(Array))
      args = (s[0] == :call) ? s[2] : s[3]
      args.each { |m| (@incl[cls] ||= []) << m if m.is_a?(Symbol) }
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
    cs, all = callees(recv_ty, name)
    return TS_TOP if cs == :unknown
    cs.each do |c, m|
      i = 0
      argtypes.each { |at| grow_param([c, m, i], at); i += 1 }
    end
    rt = all ? nil : TS_TOP     # an unresolved receiver class -> result could be anything
    cs.each { |c, m| rt = join(rt, @return_types[[c, m]]) }
    rt
  end

  def analyze(prog)
    @cur_class = nil
    @cur_returns = nil
    @safe = compute_safe(prog)
    build_methods(prog)
    @param_types  = {}     # [class,name,i] => class-set
    @return_types = {}     # [class,name]   => class-set
    iter = 0
    loop do
      iter += 1
      @changed = false
      @types = {}
      @gen = {}
      @cur_class = :Object                        # top-level self is main, an Object
      st = st0; st[:v][:self] = { :Object => true }
      eval(prog, st)
      break if !@changed || iter > 40
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
    io.puts "#{pad}(#{node[0].inspect}#{suffix}"
    (node[1..-1] || []).each { |c| dump_node(c, indent + 1, io) }
    io.puts "#{pad})"
  end
end
