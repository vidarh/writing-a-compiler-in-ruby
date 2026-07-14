# frozen_string_literal: true
#
# Whole-program, FLOW-SENSITIVE type inference (points-to on receiver classes) + generation tracking.
# Inference-first; devirt is a later consumer. Verified via `--type-ast`. Runs in `compile` before codegen.
# See docs/devirt_plan.md.
#
# Flow-sensitive because the generation model is: a class's vtable state is ordered by program points
# ("A={foo} before bar, A={foo,baz} after"), and an object's type must be pinned to the state observable
# at each point. The analysis threads a STATE forward through control flow, forks at branches, joins at
# merges, and fixpoints at loops. Each expression is annotated with its type IN the state at its point.
#
# STATE = { var_sym => class-set }.  class-set = TS_TOP (any class) | Hash{class-tag=>true} | nil (bottom).
# Sound "may": unknown -> TS_TOP. (Generation state is added to STATE next, once types check out.)

class TypeInference
  TS_TOP = :__top
  TS_NIL = { :NilClass => true }

  def initialize
    @types = {}   # node.object_id -> class-set at its evaluation point (for the dump)
  end
  attr_reader :types

  # ---- class-set lattice ----
  def join(a, b)
    return TS_TOP if a == TS_TOP || b == TS_TOP
    return b if a.nil?
    return a if b.nil?
    o = {}
    a.each { |k, _| o[k] = true }
    b.each { |k, _| o[k] = true }
    o
  end

  def ts_eq(a, b)
    return true if a.equal?(b)
    return false if a == TS_TOP || b == TS_TOP || a.nil? || b.nil?
    return false if a.length != b.length
    a.each_key { |k| return false if !b[k] }
    true
  end

  def ts_str(ts)
    return "TOP" if ts == TS_TOP
    return "BOT" if ts.nil? || ts.empty?
    "{" + ts.keys.map { |k| k.to_s }.sort.join(",") + "}"
  end

  # ---- flow-sensitive state (a var->type-set map) ----
  # merge: per-variable join over the union of keys; a var present in only one branch is nil (Ruby: an
  # unassigned-in-this-path local reads as nil) on the other side -> join with TS_NIL. Returns [merged, changed?]
  def merge_states(a, b)
    out = {}
    changed = false
    keys = {}
    a.each_key { |k| keys[k] = true }
    b.each_key { |k| keys[k] = true }
    keys.each_key do |k|
      av = a.key?(k) ? a[k] : TS_NIL
      bv = b.key?(k) ? b[k] : TS_NIL
      out[k] = join(av, bv)
    end
    [out, changed]
  end

  def states_eq(a, b)
    return false if a.length != b.length
    a.each { |k, v| return false if !b.key?(k) || !ts_eq(v, b[k]) }
    true
  end

  # ---- eval: returns [type-set, new_state]; threads state through side effects (assigns, calls) ----
  def eval(node, st)
    return [TS_NIL, st] if node == :nil
    return [{ :TrueClass => true }, st]  if node == :true
    return [{ :FalseClass => true }, st] if node == :false
    if node.is_a?(Symbol)
      return [st.key?(node) ? st[node] : TS_TOP, st]   # local/param/const ref
    end
    return [TS_TOP, st] if !node.is_a?(Array)
    t = node[0]
    ty, st = eval_node(node, t, st)
    @types[node.object_id] = ty
    [ty, st]
  end

  def eval_node(node, t, st)
    case t
    when :array then [{ :Array => true }, eval_children(node, 1, st)]
    when :hash  then [{ :Hash => true },  eval_children(node, 1, st)]
    when :float then [{ :Float => true }, st]
    when :sexp
      inner = node[1]
      if inner.is_a?(Array) && inner[0] == :call && inner[1] == :__get_string
        [{ :String => true }, st]
      elsif inner.is_a?(Symbol) && inner.to_s.start_with?("__FSL")
        [{ :String => true }, st]
      elsif inner.is_a?(Symbol) && inner.to_s.start_with?("__S_")
        [{ :Symbol => true }, st]
      elsif inner.is_a?(Integer)
        [{ :Integer => true }, st]
      else
        # raw asm: taint any vars it assigns to TOP (sound), value unknown
        [TS_TOP, taint_sexp(node, st)]
      end
    when :assign
      tv, st2 = eval(node[2], st)
      if node[1].is_a?(Symbol)
        st2 = st2.dup
        st2[node[1]] = tv
      else
        _, st2 = eval(node[1], st2)   # index/ivar assign target: eval for effects
      end
      [tv, st2]
    when :do
      eval_seq(node, 1, st)
    when :if
      te, s1 = eval(node[1], st)                       # cond
      tt, sthen = eval_arm(node[2], s1)
      tf, selse = eval_arm(node[3], s1)
      merged, = merge_states(sthen, selse)
      [join(tt, tf), merged]
    when :ternif
      _, s1 = eval(node[1], st)
      alt = node[2]
      if alt.is_a?(Array) && alt[0] == :ternalt
        tt, sthen = eval_arm(alt[1], s1)
        tf, selse = eval_arm(alt[2], s1)
        merged, = merge_states(sthen, selse)
        [join(tt, tf), merged]
      else
        eval_arm(alt, s1)
      end
    when :while, :until
      eval_loop(node, st)
    when :callm
      st = node[1] ? eval(node[1], st)[1] : st          # receiver
      st = eval_children(node, 3, st)                   # args live at node[3]
      # C.new -> instance of C; else unknown result (interprocedural return typing is a later step)
      ty = (node[2] == :new && node[1].is_a?(Symbol) && ti_const?(node[1])) ? { node[1] => true } : TS_TOP
      [ty, st]
    when :call
      st = eval_children(node, 2, st)
      [TS_TOP, st]
    when :defm
      analyze_body(node, node[1].is_a?(Symbol) ? 2 : 2)  # nested scope, own state
      [node[1].is_a?(Symbol) ? { :Symbol => true } : TS_TOP, st]
    when :defun
      analyze_body(node, 1)
      [{ :Proc => true }, st]
    when :class, :module
      # class/module body executes in-line (its defs run now); thread state through its body statements.
      bodyi = (t == :class) ? 3 : 2
      st = eval(node[2], st)[1] if t == :class && node[2].is_a?(Array)  # superclass expr
      eval_seq(node, bodyi, st)
    else
      [TS_TOP, eval_children(node, 1, st)]
    end
  end

  # evaluate children from index i, threading state; ignore their types
  def eval_children(node, i, st)
    while i < node.length
      st = eval(node[i], st)[1] if node[i].is_a?(Array) || node[i].is_a?(Symbol)
      i += 1
    end
    st
  end

  # sequence: thread state, value = last child's type
  def eval_seq(node, i, st)
    last = TS_NIL
    while i < node.length
      c = node[i]
      if c.is_a?(Array) || c.is_a?(Symbol)
        last, st = eval(c, st)
      end
      i += 1
    end
    [last, st]
  end

  # an if/ternary arm: may be nil (missing arm -> value nil, state unchanged), a :do, or an expression
  def eval_arm(arm, st)
    return [TS_NIL, st] if arm.nil?
    eval(arm, st)
  end

  # loop: fixpoint the body's effect on state (bounded), value nil
  def eval_loop(node, st)
    _, st = eval(node[1], st) if node[1].is_a?(Array) || node[1].is_a?(Symbol)  # cond
    body = node[2]
    guard = 0
    cur = st
    while guard < 50
      guard += 1
      _, after = eval_arm(body, cur)
      merged, = merge_states(cur, after)
      break if states_eq(merged, cur)
      cur = merged
    end
    [TS_NIL, cur]
  end

  def taint_sexp(node, st)
    st = st.dup
    walk_taint(node, st)
    st
  end
  def walk_taint(node, st)
    return if !node.is_a?(Array)
    st[node[1]] = TS_TOP if node[0] == :assign && node[1].is_a?(Symbol)
    node.each { |c| walk_taint(c, st) if c.is_a?(Array) }
  end

  def ti_const?(sym)
    s = sym.to_s
    return false if s.length == 0
    b = s.getbyte(0)
    b >= 65 && b <= 90
  end

  # analyze a nested scope (defm/defun body) with a fresh state: params enter as TOP (interprocedural
  # param typing is a later step). argi = index of the arg list.
  def analyze_body(node, argi)
    st = {}
    args = node[argi]
    if args.is_a?(Array)
      args.each { |a| st[a] = TS_TOP if a.is_a?(Symbol) }
    end
    eval_seq(node, argi + 1, st)
  end

  def analyze(prog)
    eval(prog, {})
    self
  end

  # ---- annotated-AST dump ----
  def dump(prog, io = STDOUT)
    dump_node(prog, 0, io)
  end
  def dump_node(node, indent, io)
    pad = "  " * indent
    if !node.is_a?(Array)
      io.puts "#{pad}#{node.inspect}"
      return
    end
    ann = @types[node.object_id]
    suffix = ann ? "   :: #{ts_str(ann)}" : ""
    io.puts "#{pad}(#{node[0].inspect}#{suffix}"
    node[1..-1].each { |c| dump_node(c, indent + 1, io) }
    io.puts "#{pad})"
  end
end
