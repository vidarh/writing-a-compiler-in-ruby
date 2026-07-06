
require 'ast'
require 'scanner'

# 
# Parts of the compiler class that mainly transform the source tree
#
# Ideally these will be broken out of the Compiler class at some point
# For now they're moved here to start refactoring.
#

class Compiler
  include AST

  # Rewrite pattern matching :in clauses into :when clauses with conditions
  # Transforms [:in, [:pattern, ConstName, [:pattern_key, :a], ...], body]
  # Into: [:when, condition_with_bindings, body]
  #
  # IMPORTANT: This runs in compile() AFTER preprocess(), which means it runs AFTER
  # find_vars/rewrite_env_vars. Pattern-bound variables won't be identified for closure
  # capture, so they won't work correctly in nested closures.
  # See rewrite_env_vars() and docs/KNOWN_ISSUES.md for details.
  def rewrite_pattern_matching(exp)
    # First pass: Find and wrap case statements containing :in nodes
    exp.depth_first do |e|
      next :skip if e[0] == :sexp

      if e[0] == :case && e.size >= 3 && e[2].is_a?(Array)
        # Check if any branch is an :in node
        has_in = e[2].any? { |branch| branch.is_a?(Array) && branch[0] == :in }

        if has_in
          value_expr = e[1]
          case_branches = e[2]
          else_clause = e[3] if e.size > 3

          # Create new case that uses __case_value
          new_case = [:case, :__case_value, case_branches]
          new_case << else_clause if else_clause

          # Wrap in :let with proper :do block structure:
          # [:let, [:__case_value], [:do, assign, case_stmt]]
          e[0] = :let
          e[1] = [:__case_value]
          e[2] = [:do,
            [:assign, :__case_value, value_expr],
            new_case
          ]
          # Remove any extra elements
          e.slice!(3..-1) if e.size > 3

          # Skip further processing of this node to avoid infinite loop
          next :skip
        end
      end
    end

    # Second pass: Transform :in nodes to :when nodes
    exp.depth_first do |e|
      next :skip if e[0] == :sexp

      # Find :in nodes with bare name patterns (e.g., in a)
      if e[0] == :in && e[1].is_a?(Symbol)
        var_name = e[1]
        body = e[2]

        # Transform to: when (var_name = __case_value; true) then body end
        # This always matches and binds the value to the variable
        binding = [:do, [:assign, var_name, :__case_value], [:sexp, true]]

        # Replace :in with :when
        e[0] = :when
        e[1] = binding
        # e[2] remains the body
      end

      # Find :in nodes with :as_pattern (e.g., in Integer => n)
      if e[0] == :in && e[1].is_a?(Array) && e[1][0] == :as_pattern
        as_pattern = e[1]
        type_name = as_pattern[1]
        var_name = as_pattern[2]
        body = e[2]

        # Transform to: when (__case_value.is_a?(TypeName) && (var = __case_value; true))
        type_check = [:callm, :__case_value, :is_a?, [type_name]]
        binding = [:do, [:assign, var_name, :__case_value], [:sexp, true]]
        condition = [:and, type_check, binding]

        # Replace :in with :when
        e[0] = :when
        e[1] = condition
        # e[2] remains the body
      end

      # Find :in nodes with :pattern children (constant-qualified patterns)
      if e[0] == :in && e[1].is_a?(Array) && e[1][0] == :pattern
        pattern = e[1]
        const_name = pattern[1]
        pattern_elements = pattern[2..-1]
        body = e[2]

        # Build variable bindings and value checks
        bindings = []
        checks = []

        pattern_elements.each do |elem|
          if elem.is_a?(Array) && elem[0] == :pattern_key
            # Keyword shorthand: a: binds key :a to variable a
            var_name = elem[1]
            # Create: var_name = __case_value[:var_name]
            bindings << [:assign, var_name, [:callm, :__case_value, :[], [[:sexp, var_name.inspect.to_sym]]]]
          elsif elem.is_a?(Array) && elem[0] == :pair
            # Full key-value: a: 0 checks __case_value[:a] == 0
            key = elem[1]
            expected_value = elem[2]
            # Create: __case_value[key] == expected_value
            checks << [:eq, [:callm, :__case_value, :[], [key]], expected_value]
          elsif elem.is_a?(Array) && elem[0] == :hash_splat
            # Hash splat: ** or **rest
            # In pattern matching, this allows additional keys beyond those checked
            # If a variable is provided, it should capture remaining keys
            # For now, we just ignore it (allows extra keys by default)
            # TODO: Implement proper rest binding if variable name provided
            rest_var = elem[1]
            # Future: bind remaining keys to rest_var if needed
          end
        end

        # Create condition: __case_value.is_a?(ConstName) && checks && bindings
        type_check = [:callm, :__case_value, :is_a?, [const_name]]
        condition = type_check

        # Add value checks
        checks.each do |check|
          condition = [:and, condition, check]
        end

        # Add bindings
        if !bindings.empty?
          binding_block = [:do] + bindings + [[:sexp, true]]
          condition = [:and, condition, binding_block]
        end

        # Replace :in with :when
        e[0] = :when
        e[1] = condition
        # e[2] remains the body
      end

      # Find :in nodes with bare :hash patterns (e.g., in a: 1, b: 2)
      if e[0] == :in && e[1].is_a?(Array) && e[1][0] == :hash
        hash_pattern = e[1]
        pairs = hash_pattern[1..-1]
        body = e[2]

        # Build conditions for each key-value pair
        # Each pair is [:pair, [:sexp, :key], value]
        checks = []
        pairs.each do |pair|
          key = pair[1]
          expected_value = pair[2]
          # Create: __case_value[key] == expected_value
          checks << [:eq, [:callm, :__case_value, :[], [key]], expected_value]
        end

        # Combine all checks with && (and)
        # Start with type check: __case_value.is_a?(Hash)
        type_check = [:callm, :__case_value, :is_a?, [:Hash]]
        condition = type_check
        checks.each do |check|
          condition = [:and, condition, check]
        end

        # Replace :in with :when
        e[0] = :when
        e[1] = condition
        # e[2] remains the body
      end

      # Handle bare hash splat pattern: in ** or in **rest
      # This matches any hash
      if e[0] == :in && e[1].is_a?(Array) && e[1][0] == :hash_splat
        hash_splat = e[1]
        rest_var = hash_splat[1]
        body = e[2]

        # Match any hash
        type_check = [:callm, :__case_value, :is_a?, [:Hash]]
        condition = type_check

        # If rest_var is provided, bind it to the matched hash
        if rest_var
          binding = [:do, [:assign, rest_var, :__case_value], [:sexp, true]]
          condition = [:and, condition, binding]
        end

        # Replace :in with :when
        e[0] = :when
        e[1] = condition
        # e[2] remains the body
      end
    end
    exp
  end

  # Expand block_given? at TRANSFORM time (it used to be a compile-time special case emitting a
  # textual __closure__ read): running before rewrite_let_env lets the env-capture machinery box
  # __closure__ per context, so block_given? inside a BLOCK correctly reports the DEFINING
  # METHOD's block (the lambda ABI's own slot 2 now carries the call-time block instead --
  # see full_params in rewrite_lambda). Skips raw sexps and matches both the bare-symbol and
  # no-arg call forms.
  def rewrite_block_given(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      i = 0
      while i < e.length
        c = e[i]
        # Never rewrite a METHOD-NAME slot: `Kernel.block_given?` carries the bare symbol at
        # :callm slot 2, and replacing it left an :if node as the dispatch target -> garbage
        # call -> SIGSEGV (kernel/block_given_spec's KernelBlockGiven fixture). A receiver-full
        # call stays a normal runtime dispatch.
        is_method_name = (i == 2 && (e[0] == :callm || e[0] == :safe_callm)) ||
                         (i == 1 && e[0] == :call && !c.is_a?(Array))
        if !is_method_name &&
           (c == :"block_given?" || (c.is_a?(Array) && c[0] == :call && c[1] == :"block_given?"))
          e[i] = E[:if, [:ne, :__closure__, 0], :true, :false]
        end
        i += 1
      end
    end
    exp
  end

  # For 'bare' blocks, or "Proc" objects created with 'proc', we
  # replace the standard return with ":preturn", which ensures the
  # return is forced to exit the defining scope, instead of "just"
  # exiting the block itself and then Proc#call.
  #
  # FIXME: Note that this does *not* attempt to detect an "escaped"
  # block that is returning outside of where it should. At some point
  # we need to add a way of handling this (e.g. MRI raises a LocalJumpError),
  # but that is trickier to do in a sane way (one option would be
  # to keep track of any blocks that get defined, and for any return
  # from a scope that have defined this to mark the created "Proc"
  # objets accordingly).
  #
  def rewrite_proc_return(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # A nested LAMBDA's `return` is LOCAL to the lambda (Ruby lambda semantics) -- do not
      # convert it to a method-frame preturn. Without this boundary, a `-> { return }` inside
      # a proc (e.g. rubyspec it-blocks) unwound to the enclosing method's frame instead of
      # returning from the lambda (language/return_spec crashed; standalone runs exited with
      # garbage status). Nested :proc nodes DO keep converting -- return inside a proc-in-a-proc
      # still returns from the defining method.
      next :skip if e[0] == :lambda && (e[1].nil? || e[1] == :block || e[1].is_a?(Array))
      if e[0] == :return
        e[0] = :preturn
      end
    end
    exp
  end

  # Rewrite `alias_method :new, :old` (a receiver-less call, so it targets the enclosing class) into the
  # same [:alias, new, old] node the `alias` keyword produces, when both names are literal symbols.
  # Routing it through the alias path means alloc_vtable_offsets emits __voff__<new> (so calling the
  # alias by name links) and compile_alias copies the vtable slot. Must run BEFORE rewrite_symbol_constant,
  # while the args are still bare colon-prefixed symbols (:":new"); dynamic forms are left as calls.
  def rewrite_alias_method(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if e[0] == :call && e[1] == :alias_method && e[2].is_a?(Array) && e[2].length == 2
        a = e[2][0]
        b = e[2][1]
        if a.is_a?(Symbol) && a.to_s[0] == ?: && b.is_a?(Symbol) && b.to_s[0] == ?:
          e.replace([:alias, a.to_s[1..-1].to_sym, b.to_s[1..-1].to_sym])
        end
      end
    end
    exp
  end

  # Rewrite a class/module-body `define_method(:name) { |args| body }` into a real [:defm,name,params,
  # body] so it reuses the full method machinery instead of the no-op define_method stub. Parses as
  # [:call,:define_method,:":name",[:proc,params,body,_,_]]. Must run BEFORE rewrite_symbol_constant
  # (needs the bare :sym). Do NOT descend into method bodies (`next :skip if e[0]==:defm`): inside a
  # method, define_method is a runtime op, and a static nested [:defm] is wrong AND crashes
  # rewrite_let_env. Non-capturing blocks (the common case) become working methods; dynamic/computed-name
  # forms fall through.
  def rewrite_define_method(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      next :skip if e[0] == :defm
      if e[0] == :call && e[1] == :define_method &&
         e[2].is_a?(Symbol) && e[2].to_s[0] == ?: &&
         e[3].is_a?(Array) && e[3][0] == :proc &&
         e[3][1].is_a?(Array) && e[3][2].is_a?(Array)
        # Only rewrite when the block has a well-formed params list AND body (both Arrays). Some block
        # forms (empty/destructured) yield a nil params or body, which would make a malformed defm that
        # crashes rewrite_let_env -- leave those as a runtime call (the no-op stub) rather than break.
        e.replace([:defm, e[2].to_s[1..-1].to_sym, e[3][1], e[3][2]])
      elsif e[0] == :call && e[1] == :define_method &&
         e[2].is_a?(Symbol) && e[2].to_s[0] == ?: &&
         e[3].is_a?(Array) && e[3][0] == :proc && e[3].length == 1
        # An EMPTY block `define_method(:m) do; end` parses to a bare [:proc] with no params/body list
        # (a non-empty block gives [:proc, params, body]). The block form above requires both to be
        # Arrays, so this fell through to the no-op define_method stub -> the method was never defined
        # and calling it crashed (null vtable slot) instead of returning nil. Define an empty method
        # (no params, body `nil`) so `define_method(:m){}` behaves like `def m; end`.
        e.replace([:defm, e[2].to_s[1..-1].to_sym, [], [:nil]])
      elsif e[0] == :call && e[1] == :define_method &&
         e[2].is_a?(Array) && e[2].length == 2 &&
         e[2][0].is_a?(Symbol) && e[2][0].to_s[0] == ?: &&
         e[2][1].is_a?(Array) && e[2][1][0] == :callm && e[2][1][1] == :Proc && e[2][1][2] == :new &&
         e[2][1][4].is_a?(Array) && e[2][1][4][0] == :proc &&
         e[2][1][4][1].is_a?(Array) && e[2][1][4][2].is_a?(Array)
        # 2-arg form `define_method(:name, Proc.new { ... })`: the parser wraps the two args in an array at
        # e[2], and the body is the Proc's block. Same well-formed-params/body guard as the block form.
        prc = e[2][1][4]
        e.replace([:defm, e[2][0].to_s[1..-1].to_sym, prc[1], prc[2]])
      end
    end
    exp
  end

  # The "expr rescue fallback" modifier parses as [:rescue_mod, expr, fallback]. It has no direct
  # code generation, so rewrite it into the equivalent begin/rescue block: run expr, and on any
  # exception evaluate fallback. The catch-all rescue clause has no class and no exception variable.
  def rewrite_rescue_mod(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # The "expr rescue fallback" modifier reduces to [:rescue, fallback, expr] (size 3), distinct
      # from a begin/def rescue *clause* [:rescue, class, var, body] (size 4+). Rewrite the modifier
      # into a begin/rescue block: run expr, and on any exception evaluate fallback.
      if e[0] == :rescue && e.size == 3
        fallback = e[1]
        body = e[2]
        if body.is_a?(Array) && body[0] == :assign
          # `a = expr rescue 1` parses with the assign INSIDE the modifier node; MRI binds the
          # modifier tighter than the assignment (`a = (expr rescue 1)`), so the FALLBACK must be
          # assigned on a raise. Hoist the assignment out and rescue just the RHS.
          e.replace([:assign, body[1],
            [:block, [], [body[2]], [:rescue, nil, nil, [fallback]], nil]])
        else
          e.replace([:block, [], [body], [:rescue, nil, nil, [fallback]], nil])
        end
      end
    end
    exp
  end

  # This replaces the old lambda handling with a rewrite.
  # The advantage of handling it as a rewrite phase is that it's
  # much easier to debug - it can be turned on and off to 
  # see how the code gets transformed.
  def rewrite_lambda(exp)
    seen = false
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # A nested :defm is its OWN scope, processed by rewrite_let_env's depth_first(:defm) ->
      # process_scope_env -> its own find_vars/rewrite_env_vars/rewrite_lambda sequence. Converting its
      # blocks HERE -- from an enclosing method's rewrite_lambda pass -- turns them into :defun before
      # the inner defm's own scope pass runs, so find_vars (which skips :defun) can no longer see the
      # blocks' captured variables: an inner block's reference to the defm's parameter was never moved
      # into the defm's __env__ and compiled to garbage (e.g. the raw __env__ pointer passed as a
      # method argument -> a wrong value, or a segfault when dispatched on). find_vars and
      # rewrite_env_vars already treat nested :defm as a scope boundary; rewrite_lambda was the one
      # pass that did not.
      next :skip if e[0] == :defm
      # A real lambda/proc node's args (e[1]) is always nil, :block, or an array. A :let variables
      # list whose first variable happens to be named `proc` or `lambda` -- e.g. [:proc, :lambda] for
      # locals `proc` and `lambda` -- is structurally identical at e[0] but has a bare Symbol at e[1];
      # don't mistake it for a proc node (that fed :lambda in as args and crashed).
      if (e[0] == :lambda || e[0] == :proc) && (e[1].nil? || e[1] == :block || e[1].is_a?(Array))
        seen = true
        # args can be an array, :block symbol, or nil
        args = e[1]
        args = E[] if !args || args == :block
        body = e[2] || nil
        rescue_clause = e[3]  # May be nil
        ensure_clause = e[4]  # May be nil

        if e[0] == :proc && body
          body = rewrite_proc_return(body)
        end

        # If there's a rescue or ensure clause, wrap the body in a block node
        # This mirrors how begin/rescue/ensure works
        # Block structure: [:block, args, body, rescue_clause, ensure_clause]
        if rescue_clause || ensure_clause
          body = E[:block, E[], body, rescue_clause, ensure_clause]
        end

        # A defun body is code-generated as a SINGLE expression (output_functions: compile_eval_arg).
        # The parser hands us the body as a statement-list, so a one-statement body that is just a bare
        # variable -- e.g. `{|x| x}` => [:x] -- would be mis-read as the node (x), i.e. a call to method
        # x, and crash. rewrite_let_env only wraps :defm bodies, so a TOP-LEVEL block is never wrapped.
        # Wrap the statement-list in :do here so it is an unambiguous block for every lambda. (:do is
        # transparent to the later env rewrites for nested blocks; already-node bodies are left alone.)
        if body.nil?
          body = E[:do]
        elsif !(body.is_a?(Array) && body[0].is_a?(Symbol) && [:do, :let, :block].include?(body[0]))
          body = E[:do, *body]
        end

        # Calculate arity correctly:
        # - Count required params (those without defaults)
        # - If any optional params exist, arity is -(required_count + 1)
        # - Otherwise arity is just the count
        required_count = 0
        has_optional = false
        args.each do |a|
          if a.is_a?(Array)
            if a[1] == :default && a[2] != :nil
              # Has a non-nil default - optional parameter
              has_optional = true
            elsif [:rest, :keyrest].include?(a[1])
              # Splat or keyword rest - makes it variable arity
              has_optional = true
            elsif [:block].include?(a[1])
              # Block parameter doesn't affect arity
            else
              required_count += 1
            end
          else
            required_count += 1
          end
        end
        len = has_optional ? -(required_count + 1) : required_count

        # Handle args that might already have default values from parser
        # Parser returns either symbols or [name, :default, value] tuples
        normalized_args = args.collect do |a|
          if a.is_a?(Array) && a[1] == :default
            # Already in [name, :default, value] format
            a
          elsif a.is_a?(Array) && [:rest, :block, :keyrest, :key, :keyreq].include?(a[1])
            # Special parameter types (splat, block, keyword args, etc.) - don't add default
            a
          elsif a.is_a?(Array) && a[0] == :destruct
            # Destructuring parameters [:destruct, :a, :b] - don't add default
            a
          else
            # Simple symbol - wrap it with default :nil
            [a, :default, :nil]
          end
        end

        # Bind a block's splat (rest) param. process_scope_env adds the `rest = __splat_to_Array(__splat,
        # numargs-ac)` prologue for :defm methods, but blocks become :defun HERE and never got it -- so
        # `{|*x|}`'s x was unbound garbage. Mirror that prologue. Proc#call invokes the defun as
        # `@addr(self, __callblk__, __env__, *args)`, so the defun has a 3-slot prefix (vs a method's 1 self):
        # with rest at full-params index rest_idx, ac = rest_idx - 2 makes __splat_to_Array collect exactly
        # the trailing user args. :__copysplat (forwarding) is left alone.
        # ABI slot 2 is the CALL-TIME block (see Proc#call). It is deliberately NOT named
        # __closure__: that name aliases to the env-captured METHOD block under
        # rewrite_env_vars, which is exactly what yield/block_given? in the block body want.
        full_params = [:self, :__callblk__, :__env__] + normalized_args
        rest_idx = nil
        rest_target = nil
        fpi = 0
        while fpi < full_params.length
          fp = full_params[fpi]
          if fp.is_a?(Array) && fp[1] == :rest && fp[0] != :__copysplat
            rest_idx = fpi
            rest_target = fp[0]
          end
          fpi += 1
        end
        if rest_idx
          full_params[rest_idx] = [:__splat, :rest]
          # Required params that FOLLOW the splat (`{ |*a, b, c| }` / `{ |a, *b, c| }`). Count them so the
          # splat collects only the MIDDLE args, and rebind each from the tail of the argument vector.
          # Without this the splat swallowed the trailing args too and the trailing params read from-the-
          # front slots (`{|*a, b|}.call(1,2,3)` gave a=[1,2,3], b=2 instead of a=[1,2], b=3). Mirrors the
          # :defm handling in process_scope_env.
          trailing = []
          ti = rest_idx + 1
          while ti < full_params.length
            tp = full_params[ti]
            # Plain required param (bare symbol) OR a required post-splat param that an earlier pass turned
            # into a nil-default ([name, :default, ...]). Skip &block ([name, :block]) and the rest itself.
            if tp.is_a?(Symbol)
              trailing << tp
            elsif tp.is_a?(Array) && tp[1] == :default
              trailing << tp[0]
            end
            ti += 1
          end
          ac = rest_idx - 2 + trailing.length
          prologue = E[:sexp, [:assign, rest_target, [:__splat_to_Array, :__splat, [:sub, :numargs, ac]]]]
          # Declare the splat local (rest_target) with a :let so body reads resolve to it. The :defm rest
          # handling in process_scope_env does the equivalent via `vars << rest_sym`; the lambda path has
          # no such vars list, so without an explicit let an in-method `{|*a| a}` assigns `a` but never
          # declares it -> reads compile as a method call ("undefined method 'a'"). At top level a later
          # pass happened to add the let; in-method lambdas never got one.
          # MERGE with the body's existing :let (find_vars wrapped the body as
          # [:let, vars(+ __tmp_proc/__wrapenv when procs nest), *stmts]).
          # The old code built a FRESH [:let, [rest_target]] and copied body[1..]
          # as statements: the original var list rode along as a bogus statement
          # and the __tmp_proc/__wrapenv declarations were LOST -- a rest-param
          # lambda creating a nested proc died at link time with
          # "undefined reference to __wrapenv" (file/printf's :kernel_sprintf
          # stabby lambda; repro test/repros/tp1.rb).
          if body.is_a?(Array) && body[0] == :let && body[1].is_a?(Array)
            newbody = E[:let, [rest_target] + body[1], prologue]
            copy_from = 2
          else
            newbody = E[:let, [rest_target], prologue]
            copy_from = 1
          end
          # Rebind trailing params from the argument tail: the j-th trailing param sits at
          # __splat[numargs-ac-2 + j] (right after the middle args). A proc invoked with too few args gives
          # a negative offset -- there is no such argument, so bind nil (MRI nil-fills for a proc).
          trailing.each_with_index do |tp, j|
            off = [:add, [:sub, [:sub, :numargs, ac], 2], j]
            off2 = [:add, [:sub, [:sub, :numargs, ac], 2], j]
            newbody << E[:assign, tp,
              E[:if, E[:ge, off, 0], E[:sexp, [:index, :__splat, off2]], :nil]]
          end
          bi = copy_from
          while bi < body.length
            newbody << body[bi]
            bi += 1
          end
          body = newbody
        end

        # Bind a &block parameter of a block/lambda (`{ |&blk| ... }`) from the __callblk__ ABI
        # slot: the block passed to THIS proc's invocation (Proc#call/#[] pass their own &blk
        # there; __call_with_self passes its explicit blkarg). `yield`/block_given? inside the
        # block reach the DEFINING METHOD's block separately, via the env-captured __closure__.
        # The binding is a plain register-safe assign -- NOT a method call: it runs before the
        # rest-param prologue, and a call here clobbers the raw numargs register that
        # `__splat_to_Array(__splat, numargs-ac)` consumes, so `{ |*a, &b| }` collected a garbage
        # count. The global always holds nil-or-proc (every publisher stores a Ruby value; the raw-0
        # initial state is unreachable because lambdas are only ever invoked through Proc methods,
        # which publish first). It is NOT a positional argument, so drop it from full_params.
        blockp = full_params.find { |a| a.is_a?(Array) && a[1] == :block }
        if blockp
          bname = blockp[0]
          full_params.delete(blockp)
          # Bind the block's own &param from the __callblk__ ABI slot: the CALL-TIME block,
          # passed per invocation by Proc#call/#[]/__call_with_self (nil when none). No global
          # channel -- re-entrant and thread/fiber-safe. (`yield`/block_given? inside the block
          # still reach the DEFINING METHOD's block via the env-captured __closure__.)
          body = E[:let, [bname],
            E[:assign, bname, :__callblk__],
            body]
        end

        # __env__[0] holds __stackframe__: the frame a non-local `return`/`break` from this
        # proc must unwind to -- the ENCLOSING METHOD's frame. Only assign it when the slot is
        # still 0 (the env is calloc'd fresh per method invocation). The method sets it when it
        # creates its first block, before any nested block runs; a nested block created inside
        # another block shares the same env, so re-running [:stackframe] here would CLOBBER the
        # method frame with the intermediate (soon-dead) block frame -- when such a block is saved
        # and invoked later (e.g. `outer{ inner{ add{ return } } }; @saved.call`), preturn then
        # jumps to a dead frame and segfaults. Guarding on 0 keeps env[0] pinned to the method.
        e.replace(
          E[:do,
            [:if, [:eq, [:index, :__env__,0], 0],
              [:assign, [:index, :__env__,0], [:stackframe]]],
            [:assign, :__tmp_proc,
              [:defun, "__lambda_#{@e.get_local[1..-1]}",
                full_params,
                body
              ]
            ],
            [:sexp, [:call, :__new_proc, [:__tmp_proc, :__env__, :self, len, :__closure__]]]
          ]
        )
      end
    end
    __nest_proc_envs(exp) if seen
    return seen
  end

  # Post-pass over rewrite_lambda's output: any generated __lambda_ defun whose body ITSELF
  # creates procs gets a per-activation wrapper env, and its creation sites are repointed at it.
  # Wrapper layout matches the root env's head (see process_scope_env): [0] = this activation's
  # frame (the break target for the procs created here), [1] = the parent env (this lambda's
  # own __env__ parameter). Without this, every proc in a method shared the single root env, so
  # env[0] was pinned to the FIRST activation that created any block: break from a nested block
  # skipped the intermediate activations' continuations, and a stored block invoked from a later
  # activation (rubyspec shared examples) unwound into a dead frame -> SIGSEGV.
  def __nest_proc_envs(n)
    return if !n.is_a?(Array)
    # A nested real method (:defm, or a non-lambda :defun) is its OWN scope with its own
    # rewrite_let_env pass -- walking into it here would repoint ITS method-level creation
    # triples at a __wrapenv that does not exist in that scope (and double-inject prologues
    # when the toplevel pass re-walks already-processed defm bodies).
    return if n[0] == :defm
    if n[0] == :defun && !(n[1].is_a?(String) && n[1].start_with?("__lambda_"))
      return
    end
    if n[0] == :defun && n[1].is_a?(String) && n[1].start_with?("__lambda_")
      body = n[3]
      if __contains_proc_node_defun?(body)
        __repoint_creations(body)
        __inject_wrapenv_prologue(body)
      end
      __nest_proc_envs(body)
      return
    end
    i = 0
    while i < n.length
      __nest_proc_envs(n[i]) if n[i].is_a?(Array)
      i += 1
    end
  end

  # After rewrite_lambda, nested procs appear as the generated __lambda_ defuns (the :proc/:lambda
  # nodes are gone). Detect them without crossing into DEEPER defuns' bodies.
  def __contains_proc_node_defun?(n)
    return false if !n.is_a?(Array)
    return false if n[0] == :class || n[0] == :module
    return false if n[0] == :defm
    return false if n[0] == :defun && !(n[1].is_a?(String) && n[1].start_with?("__lambda_"))
    return true if n[0] == :defun && n[1].is_a?(String) && n[1].start_with?("__lambda_")
    i = 0
    while i < n.length
      return true if n[i].is_a?(Array) && __contains_proc_node_defun?(n[i])
      i += 1
    end
    false
  end

  # Rewrite the creation triples DIRECTLY inside this defun body (not those inside deeper
  # defuns) to build their procs against :__wrapenv. The triple shape is fixed (emitted by
  # rewrite_lambda): [:do, <env[0] guard :if>, [:assign, :__tmp_proc, [:defun,...]], [:sexp,
  # [:call, :__new_proc, [...]]]]. The guard becomes a wrapenv-slot re-check (a no-op after the
  # prologue set it; kept for shape stability), and __new_proc's env argument becomes the wrapper.
  def __repoint_creations(n, in_defun = false)
    return if !n.is_a?(Array)
    return if n[0] == :class || n[0] == :module
    return if n[0] == :defm
    return if n[0] == :defun && !(n[1].is_a?(String) && n[1].start_with?("__lambda_"))
    if n[0] == :defun && n[1].is_a?(String) && n[1].start_with?("__lambda_")
      return if in_defun
      # descend into the created lambda's body only to find ITS creation sites? No: those belong
      # to the deeper defun and are handled when __nest_proc_envs reaches it. Stop here.
      return
    end
    if n[0] == :do && n[1].is_a?(Array) && n[1][0] == :if &&
       n[1][1].is_a?(Array) && n[1][1][0] == :eq &&
       n[1][1][1].is_a?(Array) && n[1][1][1][0] == :index && n[1][1][1][1] == :__env__ &&
       n.last.is_a?(Array) && n.last[0] == :sexp &&
       n.last[1].is_a?(Array) && n.last[1][0] == :call && n.last[1][1] == :__new_proc
      # guard: [:if, [:eq, [:index, :__env__, 0], 0], [:assign, [:index, :__env__, 0], [:stackframe]]]
      n[1][1][1][1] = :__wrapenv
      n[1][2][1][1] = :__wrapenv if n[1][2].is_a?(Array) && n[1][2][0] == :assign &&
                                    n[1][2][1].is_a?(Array) && n[1][2][1][0] == :index
      # __new_proc args: [tmp, env, self, len, closure]
      args = n.last[1][2]
      args[1] = :__wrapenv if args.is_a?(Array) && args[1] == :__env__
    end
    i = 0
    while i < n.length
      __repoint_creations(n[i], in_defun) if n[i].is_a?(Array)
      i += 1
    end
  end

  # Insert the wrapper allocation at the head of the let that declares :__wrapenv (added by
  # find_vars for proc-creating lambdas). [:stackframe] here is THIS defun activation's frame.
  def __inject_wrapenv_prologue(n)
    return false if !n.is_a?(Array)
    return false if n[0] == :class || n[0] == :module
    return false if n[0] == :defm || n[0] == :defun
    if n[0] == :let && n[1].is_a?(Array) && n[1].include?(:__wrapenv)
      n.insert(2, E[:sexp, E[:assign, :__wrapenv, E[:call, :__alloc_env, 2]]],
                  E[:sexp, E[:assign, E[:index, :__wrapenv, 0], E[:stackframe]]],
                  E[:sexp, E[:assign, E[:index, :__wrapenv, 1], :__env__]])
      return true
    end
    i = 0
    while i < n.length
      return true if n[i].is_a?(Array) && __inject_wrapenv_prologue(n[i])
      i += 1
    end
    false
  end


  # Convert :ternalt to :pair for method call keyword arguments
  # In method calls, :ternalt nodes need to be converted to :pair nodes
  # Hash/array contexts are handled by treeoutput.rb, but method args are not
  # Ternary operators (?:) use :ternalt inside :ternif and should NOT be converted
  # foo(a: 42) => [:call, [:foo, [:ternalt, :a, 42]]] => [:call, [:foo, [:pair, [:sexp, :a], 42]]]
  # foo(a:) => [:call, [:foo, [:ternalt, :a, nil]]] => [:call, [:foo, [:pair, [:sexp, :a], :a]]]
  def convert_ternalt_in_calls(exp)
    # Walk the tree and convert :ternalt to :pair only inside :call and :callm nodes
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # Only process :call and :callm nodes to convert their :ternalt arguments
      if e.is_a?(Array) && (e[0] == :call || e[0] == :callm)
        # Get arguments array index (different for :call vs :callm)
        args_index = e[0] == :call ? 2 : 3
        next unless e[args_index].is_a?(Array)

        # e[args_index] is the arguments array
        e[args_index].each do |arg|
          if arg.is_a?(Array) && arg[0] == :ternalt
            # Convert [:ternalt, key, value] to [:pair, [:sexp, :key], value]
            key = arg[1]
            value = arg[2]
            # If no value provided (keyword argument shorthand), use the key name as the value
            if value.nil?
              value = key
            end
            # key must be a symbol for keyword arguments
            if key.is_a?(Symbol)
              arg.replace(E[:pair, E[:sexp, key.inspect.to_sym], value])
            end
          end
        end
      end
    end
  end

  # Group keyword argument :pair and :hash_splat nodes into a :hash in method calls
  # After convert_ternalt_in_calls, we have [:pair, ...] nodes that need to be grouped
  # foo(a: 1, b: 2) => [:call, :foo, [[:pair, ...], [:pair, ...]]]
  #   becomes => [:call, :foo, [[:hash, [:pair, ...], [:pair, ...]]]]
  # foo(x, a: 1) => [:call, :foo, [x, [:pair, ...]]]
  #   becomes => [:call, :foo, [x, [:hash, [:pair, ...]]]]
  # foo(**h) => [:call, :foo, [[:hash_splat, h]]]
  #   becomes => [:call, :foo, [h]] (just use h directly as hash)
  def group_keyword_arguments(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # Only process :call and :callm nodes
      if e.is_a?(Array) && (e[0] == :call || e[0] == :callm)
        args_index = e[0] == :call ? 2 : 3
        next unless e[args_index].is_a?(Array)

        args = e[args_index]
        # A sole collection-literal argument can arrive UNWRAPPED in the args slot -- `m({...}) { block }`
        # and `m([...]) { block }` leave the bare [:hash,...]/[:array,...] node there instead of a
        # one-element arg list (the block path in treeoutput skips the single-arg wrapping). Iterating it
        # as an arg list reads `:hash`/`:array` and the following elements as separate args, and the
        # trailing :pair then gets re-wrapped into a bogus nested [:hash, [:hash, ...]] -> compile_hash
        # errors ("Literal Hash must contain key value pairs"). It is ONE argument: wrap it and move on.
        if args[0] == :hash || args[0] == :array
          e[args_index] = [args]
          next
        end
        new_args = []
        pairs_and_splats = []

        args.each do |arg|
          if arg.is_a?(Array) && (arg[0] == :pair || arg[0] == :hash_splat)
            pairs_and_splats << arg
          else
            # Non-keyword argument - flush any accumulated pairs
            if !pairs_and_splats.empty?
              new_args << E[:hash, *pairs_and_splats]
              pairs_and_splats = []
            end
            new_args << arg
          end
        end

        # Flush remaining pairs/splats at end
        if !pairs_and_splats.empty?
          new_args << E[:hash, *pairs_and_splats]
        end

        # Replace args array
        e[args_index] = new_args
      end
    end
  end

  # Rewrite defined? operator to return appropriate string or false
  # This must happen BEFORE rewrite_strconst so strings get properly handled
  def rewrite_defined(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if e.is_a?(Array) && e[0] == :"defined?"
        arg = e[1]
        result = nil   # nil means "undefined" (Ruby's defined? returns nil, NOT false, for undefined)

        # Analyze the argument to classify it. Cases we cannot decide at compile time (constants, methods,
        # arbitrary calls) return nil -- imperfect but Ruby-correct for the undefined case and, crucially,
        # never crashes. (Constant/method liveness would need a runtime check.)
        methodish = nil
        if arg.is_a?(Array)
          case arg[0]
          when :assign, :massign, :iasgn, :op_asgn, :or_asgn, :and_asgn,
               :mul_assign, :div_assign, :mod_assign, :pow_assign,
               :and_bitwise_assign, :or_bitwise_assign, :xor_assign,
               :shl_assign, :shr_assign
            result = "assignment"
          when :array, :hash, :str, :int, :float, :sexp, :and, :or, :not
            result = "expression"
          when :call
            if arg[1] == :yield
              result = :yield_check
            else
              methodish = arg[1]
            end
          when :callm, :safe_callm
            methodish = arg[2]
          else
            # Raw operator nodes (rewrite_operators runs later): a defined
            # operator method reads as "method" (e.g. defined?(1 + 1)).
            methodish = arg[0] if arg[0].is_a?(Symbol) && @vtableoffsets.get_offset(arg[0])
          end
          # A known method name classifies as "method" (approximation: presence in
          # ANY vtable; MRI checks the actual receiver). Unknown -> nil (undefined).
          if methodish.is_a?(Symbol)
            result = "method" if @vtableoffsets.get_offset(methodish)
          end
        elsif arg == :yield
          result = :yield_check
        elsif arg == :nil
          result = "nil"
        elsif arg == :true
          result = "true"
        elsif arg == :false
          result = "false"
        elsif arg == :self
          result = "self"
        elsif arg.is_a?(Integer) || arg.is_a?(String)
          result = "expression"
        elsif arg.is_a?(Symbol)
          nm = arg.to_s
          c0 = nm[0].ord
          if c0 == 58                                     # :sym literal
            result = "expression"
          elsif c0 >= 65 && c0 <= 90                      # Constant
            result = "constant" if @classes.member?(arg) || @global_constants.member?(arg)
          elsif c0 != 64 && c0 != 36                      # not @ivar / $gvar (stay nil)
            # bare identifier: a known method name reads as "method"; otherwise nil.
            # (Local variables are not tracked by this pass -- see docs.)
            result = "method" if @vtableoffsets.get_offset(arg)
          end
        end

        # Replace with a value node. nil is the bare symbol :nil (the old E[:false] built [:false], which
        # compiled as a CALL to method `false`). For a type string, build the string-constant getter here
        # directly: rewrite_strconst runs after us but skips :sexp, so it would not process a wrapped string.
        if result.nil?
          # Ruby's defined? returns nil (falsy) for undefined. A bare :nil is only falsy when compiled in
          # normal value context; :do/:sexp wrappers make it truthy. [:and, :nil, :nil] evaluates :nil
          # normally and short-circuits to a genuine (falsy) nil.
          e.replace(E[:and, :nil, :nil])
        elsif result == :yield_check
          # defined?(yield) is "yield" exactly when a block was passed; runtime test.
          # block_given? here is rewritten by the later rewrite_block_given pass.
          lab = @string_constants["yield"]
          if !lab
            lab = @e.get_local
            @string_constants["yield"] = lab
          end
          e.replace(E[:if, [:call, :"block_given?", []],
                      [:sexp, [:call, :__get_string, lab.to_sym]], :nil])
        else
          lab = @string_constants[result]
          if !lab
            lab = @e.get_local
            @string_constants[result] = lab
          end
          e.replace(E[:sexp, E[:call, :__get_string, lab.to_sym]])
        end
      end
    end
  end

  # Re-write string constants outside %s() to
  # %s(call __get_string [original string constant])
  def rewrite_strconst(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      # A [:float, "<decimal>"] node's string is a rodata `.double` operand for the assembler, NOT a
      # runtime String literal -- leave it intact (rewriting it to __get_string emitted a garbage
      # `.double [:sexp,...]`).
      next :skip if e[0] == :float
      # Keep the require name readable: a :require_missing marker's string is only used
      # for the "Unable to open" build error / runtime LoadError message.
      next :skip if e[0] == :require_missing
      is_call = e[0] == :call || e[0] == :callm
      e.each_with_index do |s,i|
        if s.is_a?(String)
          lab = @string_constants[s]
          if !lab
            lab = @e.get_local
            @string_constants[s] = lab
          end
          e[i] = E[:sexp, E[:call, :__get_string, lab.to_sym]]

          # FIXME: This is a horrible workaround to deal with a parser
          # inconsistency that leaves calls with a single argument with
          # the argument "bare" if it's not an array, which breaks with
          # this rewrite.
          e[i] = E[e[i]] if is_call && i > 1
        end
      end
    end
  end


  def symbol_name(v)
    s = "__S_#{clean_method_name(v)}"
    s.to_sym
  end


  # Rewrite a numeric constant outside %s() to
  # %s(sexp (__int num))
  def rewrite_integer_constant(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      is_call = e[0] == :call || e[0] == :callm
      # FIXME: e seems to get aliased by v
      ex = e
      e.each_with_index do |v,i|
        if v.is_a?(Integer)
          ex[i] = E[:sexp, v*2+1]


          # FIXME: This is a horrible workaround to deal with a parser
          # inconsistency that leaves calls with a single argument with
          # the argument "bare" if it's not an array, which breaks with
          # this rewrite.
          ex[i] = E[ex[i]] if is_call && i > 1
        end
      end
    end
  end

  # Rewrite a symbol constant outside %s() to
  # %s(sexp __[num]) and output a list later
  def rewrite_symbol_constant(exp)
    @symbols = Set[]
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      is_call = e[0] == :call || e[0] == :callm
      # FIXME: e seems to get aliased by v
      ex = e
      e.each_with_index do |v,i|
        next unless v.is_a?(Symbol)
        name = v.to_s
        if name[0] == ?:
          if !@symbols.member?(v)
            @symbols << name[1..-1]
          end
          ex[i] = E[:sexp, symbol_name(name[1..-1])]

          # FIXME: This is a horrible workaround to deal with a parser
          # inconsistency that leaves calls with a single argument with
          # the argument "bare" if it's not an array, which breaks with
          # this rewrite.
          ex[i] = E[ex[i]] if is_call && i > 1
        end
      end
    end
  end

  
  # Rewrite operators that should be treated as method calls
  # so that e.g. (+ 1 2) is turned into (callm 1 + 2)
  #
  def rewrite_operators(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp

      if e[0].is_a?(Symbol) && OPER_METHOD.member?(e[0].to_s)
        # Handle unary minus specially: [:-, operand] => [:callm, 0, :-, [operand]]
        if e[0] == :- && e.length == 2
          e[3] = E[e[1]]  # args = [operand]
          e[2] = :-       # method = :-
          e[1] = E[:sexp, 1]  # object = 0 (tagged as fixnum: 0*2+1 = 1)
          e[0] = :callm   # op = :callm
        # Handle unary plus: [:+, operand] => [:callm, operand, :+@, []]
        elsif e[0] == :+ && e.length == 2
          e[3] = E[]       # args = []
          e[2] = :+@       # method = :+@
          e[1] = e[1]      # object = operand
          e[0] = :callm    # op = :callm
        else
          e[3] = E[e[2]] if e[2]
          e[2] = e[0]
          e[0] = :callm
        end
      end
    end
  end

  # 1. If I see an assign node, the variable on the left hand is defined
  #    for the remainder of this scope and on any sub-scope.
  # 2. If a sub-scope is lambda, any variable that is _used_ within it
  #    should be transferred from outer active scopes to env.
  # 3. Once all nodes for the current scope have been processed, a :let
  #    node should be added with the remaining variables (after moving to
  #    env).
  # 4. If this is the outermost node, __env__ should be added to the let.

  def in_scopes(scopes, n)
    scopes.reverse.collect {|s| s.member?(n) ? s : nil}.compact
  end

  def is_special_name?(v)
    # FIXME: This is/was broken because it'd prevent valid variable names
    # like "eq" from being recognized. The proper fix to this is to type
    # the AST properly, but for now this seems to be an improvement
    #Compiler::Keywords.member?(v) ||
      c = v.to_s[0]   # nil for an empty name (e.g. the empty symbol)
      v == :nil || v == :self ||
      c == ?@ ||
      v == :true || v == :false  || (c && c < ?a)
  end

  def push_var(scopes, env, v)
    sc = in_scopes(scopes,v)
    if sc.size == 0 && !env.member?(v) && !is_special_name?(v)
      scopes[-1] << v 
    end
  end

  # True if the tree contains a :proc/:lambda NODE (args slot nil/:block/Array -- same shape
  # test rewrite_lambda uses, so a :let list whose first var is named `proc` doesn't count).
  def __contains_proc_node?(n)
    return false if !n.is_a?(Array)
    # A class/module body executes against a REBOUND __env__ (compile_class) -- procs inside it
    # belong to that scope, not to any enclosing lambda, so they must not make the enclosing
    # lambda an allocator (matching the :class boundaries in the __nest_proc_envs walkers).
    return false if n[0] == :class || n[0] == :module
    if (n[0] == :proc || n[0] == :lambda) && (n[1].nil? || n[1] == :block || n[1].is_a?(Array))
      return true
    end
    i = 0
    while i < n.length
      return true if n[i].is_a?(Array) && __contains_proc_node?(n[i])
      i += 1
    end
    false
  end

  def find_vars_ary(ary, scopes, env, freq, in_lambda = false, in_assign = false, current_params = Set.new)
    vars = []
    ary.each do |e|
      vars2, env2 = find_vars(e, scopes, env, freq, in_lambda, in_assign, current_params)
      vars += vars2
      env  += env2
    end
    return vars
  end

  # FIXME: Rewrite using "depth first"?
  def find_vars(e, scopes, env, freq, in_lambda = false, in_assign = false, current_params = Set.new)
    return [], env if !e
    e = [e] if !e.is_a?(Array)
    e.each do |n|
      if n.is_a?(Array)
        # :defm/:defun have their own scopes (processed by rewrite_let_env's depth_first(:defm)); :required
        # nodes are inlined library files. When find_vars scans a TOP-LEVEL scope it must not descend into
        # any of them, or it captures/rewrites library + method-body vars into the top-level __env__.
        next if n[0] == :defun || n[0] == :required
        if n[0] == :defm
          # A nested def's BODY is its own scope -- never scan it from here (see the comment above).
          # But a SINGLETON def's receiver (`def recv.name`, e[1] == [recv, name]) is evaluated in the
          # ENCLOSING scope, so scan it as an ordinary read: a receiver captured from inside a lambda
          # must be promoted into __env__ here, or rewrite_env_vars' receiver rewrite (which only
          # rewrites names already IN the env) never fires and the def's receiver compiles as a bogus
          # self-method call / garbage. Previously the capture only happened if some OTHER reference
          # to the variable happened to promote it, so `l = -> { def obj.foo; end }` worked or
          # crashed depending on where else obj was mentioned.
          if n[1].is_a?(Array) && !n[1].empty?
            _v, env = find_vars([n[1][0]], scopes, env, freq, in_lambda, false, current_params)
          end
          next
        end
        if n[0] == :assign
          target = n[1]
          if target.is_a?(Array) && target[0] == :deref
            # Constant assignment Foo::Bar = v / m::N = v: only the parent (target[1]) can be a local
            # variable. Iterating the [:deref, parent, const] node as a list would wrongly collect the
            # :deref tag and the constant name as variables. Process just the parent.
            vars1, env1 = find_vars([target[1]], scopes + [Set.new],env, freq, in_lambda, true, current_params)
          else
            vars1, env1 = find_vars(target, scopes + [Set.new],env, freq, in_lambda, true, current_params)
          end
          # Register the assignment target(s) in the CURRENT scope BEFORE analysing the RHS. Ruby declares
          # a local as soon as its assignment is parsed -- including for uses on the RHS -- so a self-
          # referential assignment such as `l = -> { l.call }` must see `l` as an already-declared local
          # while the RHS lambda is scanned, otherwise the capture is missed: `l` is not promoted into
          # __env__, the RHS lambda reads it from an uninitialised local slot, and the recursive call
          # jumps through a garbage @addr and segfaults. (Doing `l = nil` before the assignment was a
          # manual workaround for exactly this.) push_var is idempotent, so a plain `x = 5` is unaffected.
          vars1.each {|v| push_var(scopes, env, v) if !is_special_name?(v) }
          vars2, env2 = find_vars(n[2..-1], scopes + [Set.new],env, freq, in_lambda, false, current_params)
          env = env1 + env2
          vars = vars1+vars2
          vars.each {|v| push_var(scopes,env,v) if !is_special_name?(v) }
        elsif (n[0] == :lambda || n[0] == :proc) && (n[1].nil? || n[1] == :block || n[1].is_a?(Array))
          # NB: the e[1] shape test mirrors rewrite_lambda's -- a :let VARIABLE LIST whose first
          # variable is a user local named `lambda`/`proc` is structurally identical at n[0]
          # but has a bare Symbol at n[1]; treating it as a proc node mutated the var list into
          # a bogus let (with :__wrapenv appended, four spec files crashed on the debris).
          # Extract parameter names (handle arrays like [:param, default])
          params_raw = n[1] || []
          param_names = params_raw.is_a?(Array) ? params_raw.collect { |p| p.is_a?(Array) ? p[0] : p } : []
          param_scope = Set.new(param_names)
          # Pass a copy of param_scope as current_params to prevent it from being modified
          vars, env2= find_vars(n[2], scopes + [param_scope], env, freq, true, false, Set.new(param_names))

          # Clean out proc/lambda arguments from the %s(let ..) and the environment we're building
          # Use param_names (symbols) not n[1] (which may contain [:param, :default, value] tuples)
          vars -= param_names
          # Don't remove params from env2 - if they're captured by nested lambdas,
          # they need to propagate up. The rewrite_env_vars will add initialization.
          env += env2

          # Declare __tmp_proc in the let of any lambda whose body CREATES nested procs:
          # rewrite_lambda (which runs after this pass) inserts `__tmp_proc` assignments there.
          # The outermost method body gets the declaration via process_scope_env's
          # `vars << :__tmp_proc`, but a NESTED lambda's let did not -- __tmp_proc in its body
          # then aliased the let's first local slot, so creating an inner proc overwrote that
          # local with the raw lambda address (array/comparison_spec: `lhs = Array.new(3){...}`
          # inside an each-block turned lhs into a code pointer -> __NDX dispatch on it ->
          # SIGSEGV). Conditional on an actual nested proc node: declaring it in EVERY lambda
          # made a proc-free lambda's bare __tmp_proc name resolve oddly downstream (selftest:
          # "undefined method '__tmp_proc' for GenericEnumerator").
          if n[2]
            # __tmp_proc: rewrite_lambda's per-creation temp. __wrapenv: this lambda's
            # PER-ACTIVATION wrapper env [frame, parent] -- allocated in its prologue by
            # __nest_proc_envs so that procs created here capture THIS activation's frame as
            # their break target (see the env-layout comment in process_scope_env).
            # Explicit if, not a ternary (self-hosting; see bdepth note in rewrite_env_vars).
            if __contains_proc_node?(n[2])
              extra = [:__tmp_proc, :__wrapenv]
            else
              extra = []
            end
            n[2] = E[n.position,:let, vars + extra, *n[2]]
          end
        elsif n[0] == :class || n[0] == :module
          # A class/module body (n[3]) is a bare statement-LIST. The generic `find_vars(n[1..-1], ...)`
          # fallback would treat that whole list as one tagged node and DROP its first element (the first
          # body statement). A local assigned only there was then never registered, so a closure in the
          # body that captured it read an uninitialised slot -> garbage/segfault (e.g.
          # `class C; a=1; m=lambda{a}; end`). Scan the superclass expr (n[2], evaluated in the enclosing
          # scope) and then EVERY body statement, in the current scope. Matches the pre-existing intent of
          # descending into class bodies (that is how later body locals get captured), just without the
          # off-by-one that dropped the first. Same failure class as the :case handling below.
          vars, env = find_vars([n[2]], scopes, env, freq, in_lambda, false, current_params) if n[2]
          if n[3]
            body = (n[3].is_a?(Array) && n[3][0].is_a?(Array)) ? n[3] : [n[3]]
            # The class BODY executes against a REBOUND __env__ (fresh, parentless -- see
            # compile_class's closure branch); analyse it OUTSIDE any lambda context so its
            # blocks' captures/lets are computed relative to that fresh env, matching the
            # depth-0 reset in __rewrite_env_vars_r. Leaking in_lambda=true here made
            # class-in-it-block bodies hop through the fresh env's null parent (for_spec).
            vars, env = find_vars(body, scopes, env, freq, false, false, current_params)
          end
        else
          if    n[0] == :callm || n[0] == :safe_callm
            # :safe_callm (`recv&.m`) has the same node shape as :callm and MUST take this branch: the
            # generic fallback below iterates the node as a list, registering the :safe_callm tag and
            # the METHOD-NAME symbol as variables -- inside a lambda the method name then got captured
            # into __env__ (`obj&.m += 3` in a block rewrote the assignment target's method to
            # `(index __env__ k)` -> garbage dispatch -> SIGSEGV; a literal `safe_callm` local also
            # appeared in the let).
            # Wrap receiver if it's an array (AST node) to prevent element-by-element iteration
            receiver = n[1].is_a?(Array) ? [n[1]] : n[1]
            vars, env = find_vars(receiver, scopes, env, freq, in_lambda, false, current_params)

            if n[3]
              nodes = n[3]
              nodes = [nodes] if !nodes.is_a?(Array)
              nodes.each do |n2|
                vars2, env2 = find_vars([n2], scopes+[Set.new], env, freq, in_lambda, false, current_params)
                vars += vars2
                env  += env2
              end
            end

            # If a block is provided, we need to find variables there too
            if n[4]
              vars3, env3 = find_vars([n[4]], scopes, env, freq, in_lambda, false, current_params)
              vars += vars3
              env  += env3
            end
          elsif    n[0] == :call
            # n[1] is the callee. For an ordinary `f(...)` it is the function NAME -- not a
            # variable reference. Scanning it registered a phantom "variable" named after the
            # function; inside a lambda that phantom got CAPTURED into __env__, skewing the env
            # layout so the closure machinery's writes landed on a NEIGHBORING live object
            # (valgrind-clean corruption): `mock("#{x}")` in a nested block turned a sibling
            # local's array into a lambda address (array/comparison_spec SIGSEGV on lhs[0]).
            # Only a COMPUTED callee (an Array node, e.g. raw-sexp indirect calls through a
            # function-pointer expression) contains variable references worth scanning.
            if n[1].is_a?(Array)
              vars, env = find_vars([n[1]], scopes, env, freq, in_lambda, false, current_params)
            else
              vars = []
            end
            if n[2]
              nodes = n[2]
              nodes = [nodes] if !nodes.is_a?(Array)
              nodes.each do |n2|
                vars2, env2 = find_vars([n2], scopes+[Set.new], env, freq, in_lambda, false, current_params)
                vars += vars2
                env  += env2
              end
            end

            if n[3]
              vars2, env2 = find_vars([n[3]], scopes, env, freq, in_lambda, false, current_params)
              vars += vars2
              env  += env2
            end
          elsif n[0] == :deref
            # [:deref, parent, const_name] - only process parent (n[1]), not const_name (n[2])
            # Const names in deref expressions are not variable references
            # But parent could be an expression or variable that needs processing
            parent = n[1].is_a?(Array) ? [n[1]] : n[1]
            vars, env = find_vars(parent, scopes, env, freq, in_lambda, false, current_params)
          elsif n[0] == :block
            # begin/rescue/ensure: [:block, args, exps, rescue_clause, ensure_body]. Body [2] and ensure
            # [4] are BARE statement-lists (not tagged :do nodes) that run in the ENCLOSING scope, so
            # locals they assign are locals of the enclosing method. The generic n[1..-1] path treats
            # such a bare list child as a tagged node and drops its first statement, so `begin x = 1 end`
            # left x unbound and a later `x`/`x.foo` compiled to a method call. Recurse per statement in
            # the CURRENT scopes so those assignments are captured; the rescue clause [3] is a single
            # tagged node, recursed as-is.
            vars = []
            [n[2], n[4]].each do |part|
              next if !part
              part.each do |s|
                _v, env = find_vars([s], scopes, env, freq, in_lambda, false, current_params)
              end
            end
            if n[3]
              # Register each rescue clause's exception variable (`rescue => e`) as a local of the ENCLOSING
              # scope. Ruby's rescue variable is an ordinary local of the surrounding method, visible after
              # the begin/rescue; without registering it here compile_begin_rescue declared it in a throwaway
              # block-let, so `e = nil; begin ..; rescue => e; end` left the OUTER e nil (and `e.foo` after
              # the block then crashed). Handles a single [:rescue,cls,var,body] and [:rescues, r1, r2, ...].
              rescue_nodes = (n[3][0] == :rescues) ? n[3][1..-1] : [n[3]]
              rescue_nodes.each do |rn|
                next if !(rn.is_a?(Array) && rn[0] == :rescue)
                rv = rn[2]
                push_var(scopes, env, rv) if rv.is_a?(Symbol) && !is_special_name?(rv)
              end
              v3, env = find_vars([n[3]], scopes, env, freq, in_lambda, false, current_params)
              vars += v3
            end
          elsif n[0] == :case
            # [:case, cond, branches] where branches is a BARE list of [:when, test, body] clauses plus an
            # optional trailing else statement-list. The generic n[1..-1] path recurses into `branches` as
            # if it were a single tagged AST node and DROPS its first element (the first when clause), so
            # variables assigned inside case branches within a lambda were never captured into __env__ (they
            # became inaccessible locals -> wrong values, or garbage reads that crashed, e.g. Regexp.escape).
            # Flatten the condition and every branch's test + body statements into one list and scan it in a
            # single pass (matching the default call's scope/env handling).
            parts = []
            parts << n[1] if n[1]
            # n[2] is the when-clause list; a trailing else arrives as a FURTHER element
            # (n[3], a bare statement-list) -- scan every group, not just n[2].
            n[2..-1].each do |grp|
              next if !grp
              brs = (grp.is_a?(Array) && !grp.empty? && grp[0].is_a?(Array)) ? grp : [grp]
              brs.each do |br|
                if br.is_a?(Array) && br[0] == :when
                  parts << br[1] if br[1]
                  body = br[2]
                  if body.is_a?(Array) && body[0].is_a?(Array)
                    body.each { |s| parts << s }
                  elsif body
                    parts << body
                  end
                elsif br.is_a?(Array) && br[0].is_a?(Array)
                  br.each { |s| parts << s }   # else statement-list
                elsif br
                  parts << br
                end
              end
            end
            vars, env = find_vars(parts, scopes, env, freq, in_lambda, false, current_params)
          else
            vars, env = find_vars(n[1..-1], scopes, env, freq, in_lambda, false, current_params)
          end

          vars.each {|v| push_var(scopes,env,v); }
        end
      elsif n.is_a?(Symbol)
        sc = in_scopes(scopes[0..-2],n)
        freq[n] += 1 if !is_special_name?(n)
        if sc.size == 0
          push_var(scopes,env,n) if in_assign && !is_special_name?(n)
        elsif in_lambda && !current_params.include?(n)
          sc.first.delete(n)
          env << n
        end
      end
    end

    ## FIXME: putting the below on one line breaks.
    last_scope = scopes[-1]
    a = last_scope.to_a
    return a, env
  end

  # `depth` = parent hops needed to reach the ROOT env (which holds all captured variables)
  # from the CURRENT position's __env__: 0 in the method body and in level-1 blocks (their
  # __env__ parameter IS the root), +1 for each additional level of block nesting (each
  # enclosing block-creating lambda interposes its per-activation wrapper env; slot 1 is the
  # parent link -- see process_scope_env's layout comment and __nest_proc_envs).
  def __env_hops(depth)
    t = :__env__
    depth.times { t = E[:index, t, 1] }
    t
  end

  # Public entry: resets the depth-tracking state and delegates. The depth/in_lambda pair is
  # carried in INSTANCE variables saved+restored around the lambda-body recursion rather than
  # as extra defaulted parameters: the parameter form miscompiled under the self-hosted
  # compiler (the compiled selftest looped in preprocess), and ivars + locals are proven
  # constructs.
  def rewrite_env_vars(exp, env)
    @env_depth = 0
    @env_in_lambda = false
    __rewrite_env_vars_r(exp, env)
  end

  def __rewrite_env_vars_r(exp, env)
    depth = @env_depth
    in_lambda = @env_in_lambda
    seen = false
    exp.depth_first do |e|
      # A class/module BODY executes against a REBOUND __env__ (compile_class allocates a fresh
      # one with no parent link -- see the class-body closure branch). Depth accumulated from
      # lambdas OUTSIDE the class must not leak in: hop chains would dereference the fresh
      # env's parent slot (0) and crash (language/for_spec: for-loop blocks in a class body
      # inside an it-block). Recurse the body at depth 0, outside-lambda state.
      if e.is_a?(Array) && (e[0] == :class || e[0] == :module) && e[3]
        if depth > 0 || in_lambda
          @env_depth = 0
          @env_in_lambda = false
          body = (e[3].is_a?(Array) && e[3][0].is_a?(Array)) ? e[3] : [e[3]]
          body.each do |stmt|
            seen = true if stmt.is_a?(Array) && __rewrite_env_vars_r(stmt, env)
          end
          @env_depth = depth
          @env_in_lambda = in_lambda
          # superclass expr (e[2]) evaluates in the ENCLOSING scope -- let depth_first continue
          # into it via the normal path by handling it here explicitly, then skipping children.
          if e[2].is_a?(Array)
            seen = true if __rewrite_env_vars_r(e[2], env)
          end
          next :skip
        end
      end
      # Never redirect inside an inlined library (:required) subtree: a top-level capture pass redirects by
      # NAME, and a common user-captured name (a/acc/...) would get rewritten to __env__[k] inside library
      # startup code -> crash. The library's own scopes are handled separately.
      next :skip if e.is_a?(Array) && e[0] == :required
      # Handle lambda/proc/defun/defm specially - process body but not parameter list
      if e.is_a?(Array) && (e[0] == :lambda || e[0] == :proc || e[0] == :defun || e[0] == :defm)
        # Get parameter list and body index
        # defm is [:defm, name, [params], body] - params at index 2, body at index 3
        # defun is [:defun, name, [params], body] - params at index 2, body at index 3
        # lambda/proc is [:lambda, [params], body] - params at index 1, body at index 2
        if e[0] == :defun || e[0] == :defm
          param_list = e[2]
          body_index = 3
        else
          param_list = e[1]
          body_index = 2
        end

        # A singleton method def `def recv.name` carries its receiver in the name tuple
        # (e[1] == [recv, methname]). The receiver is evaluated in the ENCLOSING scope, so a captured
        # local used there (e.g. `obj = Object.new; def obj.to_i; ...` inside a block) must be redirected
        # into __env__ HERE -- the param/body handling below and the `next :skip` never touch e[1], so
        # without this the receiver stays a bare symbol and fails to resolve as a method call.
        if e[0] == :defm && e[1].is_a?(Array)
          recv = e[1][0]
          if recv.is_a?(Symbol)
            rnum = env.index(recv)
            if rnum
              e[1][0] = E[:index, __env_hops(depth), rnum]
              seen = true
            end
          elsif __rewrite_env_vars_r(recv, env)
            seen = true
          end
        end

        # Extract parameter names (handle tuples like [:param, :default, :nil])
        # Note: using .collect instead of .map (map doesn't exist in lib/core/array.rb)
        # param_list can be an array or a symbol like :block (for block arguments)
        params = param_list.is_a?(Array) ? param_list.collect { |p| p.is_a?(Array) ? p[0] : p } : []

        # Find which parameters are in env (need initialization)
        # Note: using reject with negation because .select doesn't exist in lib/core/array.rb
        captured_params = params.reject { |p| !env.include?(p) }

        # A nested method definition (:defm/:defun) begins a NEW scope. Unlike a block/lambda, a Ruby
        # `def` does NOT close over the enclosing method's locals or its __closure__/__env__ -- its body
        # has its own. So we must NOT rewrite a nested def body with the ENCLOSING env: doing so rewrote
        # the def's own `__closure__` (produced by a `yield` in the body) into the enclosing method's
        # captured `(index __env__ 1)`, so `yield` inside a singleton method defined in a method invoked
        # the WRONG block -> segfault (core/enumerable/sum_spec, uniq_spec). Only lambda/proc bodies
        # genuinely capture. (The receiver e[1] above IS evaluated in the enclosing scope and is still
        # redirected into __env__ by the code above.)
        is_nested_def = (e[0] == :defm || e[0] == :defun)

        # First, process the body to rewrite variable references. Entering a lambda from the
        # method body keeps depth 0 (its __env__ param IS the root env); entering one from
        # inside another lambda adds a parent hop (the enclosing lambda's wrapper interposes).
        # e[body_index] must be an ARRAY: a :let VARIABLE LIST whose first entry is a user
        # local named `lambda`/`proc` is structurally identical at e[0] (same hazard
        # rewrite_lambda guards against), and with :__wrapenv appended to such lists its
        # bare-symbol entries landed here as a "body" -> NoMethodError on depth_first
        # (proc/new_spec).
        if e[body_index] && e[body_index].is_a?(Array) && !is_nested_def
          # Entering a lambda from the method body keeps depth (its __env__ param IS the root
          # env); entering one from inside another lambda adds a parent hop (the enclosing
          # lambda's wrapper interposes). Explicit if, not a ternary (self-hosting).
          if in_lambda
            bdepth = depth + 1
          else
            bdepth = depth
          end
          @env_depth = bdepth
          @env_in_lambda = true
          # FIXME: seen |= ... failed to compile
          if __rewrite_env_vars_r(e[body_index], env)
            seen = true
          end
          @env_depth = depth
          @env_in_lambda = in_lambda
        end

        # Then insert initialization for captured parameters (after rewriting)
        # This way the RHS (parameter) won't be rewritten
        if !captured_params.empty? && e[body_index] && e[body_index].is_a?(Array) && !is_nested_def
          # Note: using .collect instead of .map (map doesn't exist in lib/core/array.rb)
          param_inits = captured_params.collect do |p|
            idx = env.index(p)
            if in_lambda
              E[:assign, E[:index, __env_hops(depth + 1), idx], p]
            else
              E[:assign, E[:index, __env_hops(depth), idx], p]
            end
          end

          # Insert at start of body
          body = e[body_index]
          if body.is_a?(Array) && body[0] == :let
            # Insert after let declaration
            e[body_index] = E[body.position, :let, body[1], *param_inits, *body[2..-1]]
          elsif body.is_a?(Array) && body[0] == :do
            e[body_index] = E[:do, *param_inits, *body[1..-1]]
          else
            e[body_index] = E[:do, *param_inits, body]
          end
          seen = true
        end

        next :skip  # Don't let depth_first process children (would rewrite params)
      end

      # We need to expand "yield" before we rewrite.
      # yield becomes __closure__.call(args...)
      if e.is_a?(Array) && e[0] == :call && e[1] == :yield
        seen = true
        args = e[2] || []
        args = args.is_a?(Array) ? args : [args]
        e[0] = :if
        e[1] = E[:ne, :__closure__, 0]
        e[2] = E[:callm, :__closure__, :call, args]
        e[3] = E[:call, :__raise_no_block, []]
      end

      if __rewrite_node_refs(e, env, depth)
        seen = true
      end
    end
    seen
  end

  # The per-node child rewrite, extracted from __rewrite_env_vars_r: replace each child that
  # names a captured variable with its env reference (hop-wrapped for nested-lambda depth).
  # Extraction keeps the walker function small -- the combined function repeatedly tripped a
  # layout-sensitive miscompile under the self-hosted compiler (env.index results read back as
  # garbage-truthy), the same fragility this function's historical FIXMEs dance around.
  def __rewrite_node_refs(e, env, depth)
    seen = false
      e.each_with_index do |ex, i|
        # FIXME: This is necessary in order to avoid rewriting compiler keywords in some
        # circumstances. The proper solution would be to introduce more types of
        # expression nodes in the parser
        # Skip AST operator symbols at index 0 - they're not variable references
        next if i == 0 && (ex == :index || ex == :deref)
        # Also skip :callm at position 0
        next if i == 0 && ex == :callm
        # Skip hash-pair / hash-splat node tags at position 0 so a local variable named e.g. `pair`
        # does not cause the [:pair, k, v] tag itself to be rewritten into a closure reference.
        next if i == 0 && (ex == :pair || ex == :hash_splat)
        # Likewise the literal-container node tags ([:array,...], [:hash,...], [:splat,...]). These are AST
        # node types, never variable references, but a captured local variable named `array`/`hash`/`splat`
        # would otherwise make `num = env.index(ex)` match and rewrite the TAG into an [:index,__env__,k] --
        # turning e.g. an array literal `[]`/`[1,2]` into a read of the captured variable. (Same class of bug
        # as the :pair / :hash_splat guard above; surfaced via a spec with both a `def m(*foo)` literal and a
        # captured `array` local.)
        next if i == 0 && (ex == :array || ex == :hash || ex == :splat)
        # Skip constant names in :deref nodes - they're constant/module names, not variables
        # [:deref, parent, const_name] - only skip const_name (position 2), not parent (position 1)
        # The parent might be a variable like: a = Object; a::CONST
        next if i == 2 && e[0] == :deref && ex.is_a?(Symbol)

        # Skip variable names in :pattern_key nodes - these will be handled by rewrite_pattern_matching
        # [:pattern_key, var_name] - the var_name at position 1 should not be rewritten here
        #
        # IMPORTANT LIMITATION: This prevents literal [:index, :__env__, N] in assembly, but means
        # pattern-bound variables won't be captured in __env__ for nested closures. This is because
        # find_vars runs BEFORE rewrite_pattern_matching creates the pattern bindings.
        #
        # Example that FAILS with nested closures:
        #   1.times { case {x: 42} in {x:}; 1.times { puts x }; end }  # ERROR: undefined method 'x'
        #
        # Example that WORKS (single-level closure):
        #   1.times { case {x: 42} in {x:}; puts x; end }  # OK: prints 42
        #
        # See docs/KNOWN_ISSUES.md - "Pattern Matching with Nested Closures"
        next if i == 1 && e[0] == :pattern_key && ex.is_a?(Symbol)
        # Don't rewrite a callm's METHOD NAME (slot 2) into an __env__ slot. When a local variable shadows a
        # method name (e.g. `bytes = []; "abc".bytes { |b| bytes << b }`), the captured local `bytes` is in
        # env, so without this guard rewrite_env_vars rewrites the method-name `:bytes` of `"abc".bytes(...)`
        # into `[:index,__env__,k]` -- calling the captured array as a method -> SIGSEGV. The method-name slot
        # is never a variable reference. (Only :callm slot 2; a bare `[:call, name, args]` whose name is a
        # captured proc/lambda-valued local IS legitimately rewritten, so do NOT guard :call here.)
        next if i == 2 && e[0] == :callm && ex.is_a?(Symbol)
        # Likewise a bare :call's method name (slot 1). At the top level a library-captured name can collide
        # with a user method call; never redirect a method NAME to __env__.
        next if i == 1 && e[0] == :call && ex.is_a?(Symbol)
        num = env.index(ex)
        if num
          seen = true
          e[i] = E[:index, __env_hops(depth), num]
          # If this was a BARE single argument of a call -- e.g. `m(x)` parsed as [:call,:m,:x] (not
          # [:call,:m,[:x]]) -- rewriting it in place leaves [:index,__env__,N] sitting directly in the
          # argument slot, which the caller side then reads as a 3-element ARG LIST (:index,__env__,N) and
          # passes three garbage args ("wrong number of arguments"). Wrap it back into a one-element list.
          # (Same parser-quirk fixup rewrite_strconst applies to a bare String argument.)
          e[i] = E[e[i]] if (e[0] == :call || e[0] == :callm) && i > 1
        end
      end
    seen
  end

  # Visit the child nodes as follows:
  #  * On first assign, add to the set of variables
  #  * On descending into a :lambda block, add a new "scope"
  #  * On assign inside a block (:lambda node), 
  #    * if the variable is found up the scope chain: Move it to the
  #      "env" set
  #    * otherwise add to the innermost scope
  # Finally:
  #  * Insert :let nodes at the top and at all lambda nodes, if not empty
  #    (add an __env__ var to the topmost :let if the env set is not empty.
  #  * Insert an :env node immediately below the top :let node if the env
  #    set is not empty.
  #    Alt: insert (assign __env__ (array [no-of-env-entries]))  
  # Carry out a second pass:
  #  * For all _uses_ of a variable in the env set, rewrite to
  #    (index [position])
  #    => This can be done in a separate function.

  # Build the let/env-wrapped body for a scope with parameter list `e2` and body `body_in`. Extracted
  # verbatim from the :defm handler so the SAME machinery can serve both real methods and (later) the
  # top-level/main scope. Mutates e2 in place (the rest-param marker) like the original, and RETURNS the
  # new body. The recursive rewrite_let_env on the result stays with the caller.
  def process_scope_env(e2, body_in, epos)
    args   = Set[*e2.collect{|a| a.kind_of?(Array) ? a[0] : a}]

      # Count number of "regular" arguments (non "rest", non "block")
      # FIXME: There are cleaner ways, but in the interest of
      # self-hosting, I'll do this for now.
      ac = 0
      # Count positional params that precede a splat: plain required params (bare symbols) AND
      # default-valued params ([name, :default, val] -- an Array, so the bare `!kind_of?(Array)` test
      # missed them). A default param still consumes one positional slot, so omitting it from `ac` made
      # `*rest = __splat_to_Array(__splat, numargs - ac)` collect one element too many -- the default
      # param's own value leaked into the splat (e.g. `def f(a, b=1, *r); end; f(1,2)` gave r==[2]).
      e2.each{|a| ac += 1 if (! a.kind_of?(Array)) || a[1] == :default }

      scopes = [args.dup] # We don't want "args" above to get updated

      # Locate the rest (`*x`) parameter at ANY position and record the plain required parameters that
      # FOLLOW it (`def m(a, *b, c, d)`). The old code only inspected the last two positions, so a rest
      # with two or more trailing params (`def m(a, b, *c, d, e)`) was never found: the splat prologue was
      # skipped, `*c` stayed a normal positional param, and calling it read an unbound/garbage slot ->
      # crash. Trailing required params also need REBINDING from the end of the argument list (see below),
      # because their fixed param-index slots hold the wrong (from-the-front) arguments.
      rest = nil
      rest_pos = nil
      trailing_params = []
      e2.each_with_index do |p, idx|
        if p.is_a?(Array) && p[-1] == :rest
          rest = p[0]
          rest_pos = idx
        end
      end
      if rest_pos
        ((rest_pos + 1)...e2.length).each do |idx|
          tp = e2[idx]
          trailing_params << tp if tp.is_a?(Symbol)   # plain required param; skip &block / defaults
        end
        # FIXME: This is a hacky workaround
        if rest != :__copysplat
          e2[rest_pos][0] = :__splat
        end
      end

      # We use this to assign registers
      freq   = Hash.new(0)

      s = Set.new
      # A `def ... ensure/rescue ... end` body arrives as a BARE [:block, args, stmts, ...]
      # node, not a statement list. find_vars iterates its ARGUMENT as a list, so the block
      # node's elements were visited as "statements": the :block branch never fired, the
      # generic fallback dropped the first real statement, and every lambda inside was
      # invisible to capture analysis -- no let, no captures, and (under nested envs) creation
      # triples repointed to an undeclared __wrapenv (32 rubyspec files went COMPILE_FAIL:
      # "undefined reference to __wrapenv"). Wrap it so the block node is visited AS A NODE.
      fv_body = body_in
      if fv_body.is_a?(Array) && fv_body[0] == :block && fv_body[1].is_a?(Array)
        fv_body = [fv_body]
      end
      vars,env= find_vars(fv_body,scopes,s, freq)

      env << :__closure__

      # Env layout (uniform for this root env and, later, per-activation wrapper envs of nested
      # block-creating lambdas): slot 0 = __stackframe__ (frame of the activation that ALLOCATED
      # the env -- `break`'s unwind target), slot 1 = __envparent__ (the enclosing env; 0 for
      # this root -- calloc'd, so no explicit init needed; preturn walks it to find the method
      # frame), slots 2.. = captured variables. See also Compiler#compile_preturn.
      aenv = [:__stackframe__, :__envparent__] + env.to_a
      env << :__stackframe__

      body = body_in
      prologue = nil
      vars -= args.to_a
      seen = false

      # A &block parameter must read as nil when no block was passed (MRI semantics). It otherwise
      # resolves to the raw __closure__ slot, which is 0/null when absent, so merely touching the
      # parameter (block.arity, !block, block.call) dereferenced null and segfaulted. Bind it to a
      # nilable view of the closure slot: block_given? ? __closure__ : nil. Two cases:
      #  - captured (used inside a nested closure -> lives in __env__): make its env-copy nilable below;
      #  - plain local: inject an assignment after the prologue (see further down).
      blockparam = e2.find { |a| a.is_a?(Array) && a[1] == :block }
      blockname  = blockparam ? blockparam[0] : nil
      block_nilable = E[:if, :"block_given?", :__closure__, :nil]

      if env.size > 0
        seen = rewrite_env_vars(body, aenv)

        notargs = env - args - [:__closure__]

        expos = epos
        extra_assigns = (env - notargs).to_a.collect do |a|
          ai = aenv.index(a)
          rhs = (blockname && a == blockname) ? block_nilable : a
          E[expos, :assign, E[expos,:index, :__env__, ai], rhs]
        end
        prologue = [E[:sexp, E[:assign, :__env__, E[:call, :__alloc_env,  aenv.size]]]]
        if !extra_assigns.empty?
          prologue.concat(extra_assigns)
        end
        if body.empty?
          body = [:nil]
        end
      end

      # FIXME: seen |= ... and seen = seen | ... both failed to compile.
      if rewrite_lambda(body)
        seen = true
      end

      if seen
        vars << :__env__
        vars << :__tmp_proc # Used in rewrite_lambda. Same caveats as for __env_
      end

      rest_sym = nil
      if rest && rest != :__copysplat
        # rest might be a symbol or an indexed env access [:index, :__env__, N]
        # after variable renaming.
        rest_sym = rest
        rest_target = rest  # Use original rest as assignment target

        vars << rest_sym if rest_sym.is_a?(Symbol)
        # FIXME: @bug Removing the E[] below causes segmentation fault
        rest_func =
          [E[:sexp,
           # Corrected to take into account statically provided arguments.
           [:assign, rest_target, [:__splat_to_Array, :__splat, [:sub, :numargs, ac]]]
          ]]
        # Rebind each required param that FOLLOWS the splat to its correct argument, taken from the END of
        # the argument list. __splat points at the first collected (middle) argument, and __splat_to_Array
        # gathers `numargs - ac - 2` of them, so the j-th trailing param sits at __splat[numargs-ac-2 + j].
        # Their normal param-index slots hold from-the-front args (e.g. `def m(a,*c,d); m(1,2,3,4)` bound
        # d to 3 instead of 4), so overwrite those slots here before the body runs.
        trailing_params.each_with_index do |tp, j|
          vars << tp if tp.is_a?(Symbol) && !vars.include?(tp)
          rest_func << E[:assign, tp,
            E[:sexp, [:index, :__splat, [:add, [:sub, [:sub, :numargs, ac], 2], j]]]]
        end
      else
        rest_func = nil
      end

      b3 = []
      vars.to_a.each do |v|
        next if !v.is_a?(Symbol)
        next if v.to_s.start_with?("__")
        next if v == rest_sym
        next if trailing_params.include?(v)
        b3 << E[:assign, v, :nil]
      end
      if rest_func
        b3.concat(rest_func)
      end

      if seen && prologue # seen && prologue
        b3.concat(prologue)
      end

      # Plain-local &block case (not captured into __env__): bind a real local to the nilable closure.
      # Declared in `vars`, the LocalVarScope resolves it before function.rb's __closure__ alias.
      if blockname && !env.include?(blockname)
        vars << blockname if !vars.include?(blockname)
        b3 << E[:assign, blockname, block_nilable]
      end

      # When body is a single expression node (like :block from ensure), concat would flatten its
      # contents incorrectly. Detect this case and wrap it. A single expression node has a keyword
      # symbol as its first element.
      #
      # BUT several keyword TAGS (:block, :index, :array, :hash, :include ...) are also legal local
      # variable names, so a method whose body is just that bare variable parses to a length-1 body
      # like [:block] -- indistinguishable from an empty :block node. A genuine expression node from
      # ensure/rescue carries its statements (length > 1); a bare standalone control keyword
      # (:return/:break/:next/:redo/:retry) is the only length-1 node that must still be wrapped.
      # Everything else of length 1 is a variable reference and must be concatenated.
      single_node = body.is_a?(Array) && body[0].is_a?(Symbol) && Compiler::Keywords.include?(body[0]) &&
        (body.length > 1 || [:return, :break, :next, :redo, :retry].include?(body[0]))
      if single_node
        b3 << body
      else
        b3.concat(body)
      end

      # FIXME: Compiler bug: Changing the below to "if !vars.empty?" causes seg fault.
      empty = vars.empty?
      if empty == false
        b3 = E[epos,:let, vars, *b3]
        # We store the variables by descending frequency for future use in register
        # allocation.
        # FIXME: Compiler bug: -v fails.
        b3.extra[:varfreq] = freq.sort_by {|k,v| 0 - v }.collect{|a| a.first }
      else
        b3 = E[epos, :do, *b3]
      end
      b3
  end

  def rewrite_let_env(exp)
    exp.depth_first(:defm) do |e|
      # A synthesized defm node (e.g. from rewriting define_method) is a plain Array with no #position;
      # guard the position read so we don't crash on it (nil position is acceptable here).
      epos = e.respond_to?(:position) ? e.position : nil
      e[3] = process_scope_env(e[2], e[3], epos)

      # Recursively process the rewritten body to handle nested defms (e.g., eigenclass methods)
      rewrite_let_env(e[3])

      :skip
    end

    # Handle top-level procs (those not inside any :defm). These need the SAME find_vars/rewrite_env_vars
    # capture pass that process_scope_env gives method bodies -- without it, a nested top-level block that
    # captures an enclosing block's param/local reads garbage (the param is never written to __env__). Run it
    # BEFORE rewrite_lambda (which converts :lambda->:defun), matching process_scope_env's order. find_vars
    # skips :defm/:defun/:required, so only the user top-level scope is analysed.
    tenv = nil
    if exp[0] == :do
      tvars, te = find_vars(exp, [Set.new], Set.new, Hash.new(0))
      if te && !te.to_a.empty?
        tenv = te
        rewrite_env_vars(exp, [:__stackframe__, :__envparent__] + te.to_a)
      end
    end
    if rewrite_lambda(exp)
      # If we found any procs at top level, we need to set up the environment
      # Look for the first :do or :let that wraps top-level code and add __env__ and __tmp_proc
      if exp[0] == :do
        # Check if __env__ is already declared (avoid duplicates)
        has_env = false
        exp.each do |e|
          if e.is_a?(Array) && e[0] == :let && e[1].is_a?(Array) && e[1].include?(:__env__)
            has_env = true
            break
          end
        end
        if !has_env
          # Wrap the top-level code in a let that declares __env__, __tmp_proc, and __closure__
          # __closure__ must be 0 at top level since there's no enclosing closure
          # __tmp_proc is used by rewrite_lambda to hold the temporary proc
          # __env__ must be sized to hold the captured vars (stackframe slot + each captured var), not just 2.
          envsize = tenv ? [3, ([:__stackframe__, :__envparent__] + tenv.to_a).size].max : 3
          inner = exp[1..-1].dup
          exp.clear
          exp << :do
          let_body = E[:do,
            E[:sexp, E[:assign, :__closure__, 0]],
            E[:sexp, E[:assign, :__env__, E[:call, :__alloc_env, envsize]]]]
          inner.each { |e| let_body << e }
          exp << E[:let, [:__closure__, :__tmp_proc, :__env__], let_body]
        end
      end
    end
  end

  # Runtime `Class.new(superclass)` is broken: the eigenclass dispatch of `.new` on Class does not build a
  # real class (garbage vtable/superclass), so instances get a wrong class pointer and crash on
  # inspect/is_a?/==. Intercept the literal `Class.new(...)` callm at compile time and build a proper class
  # object via __new_class_object (the helper the compiler uses for `class X < Y`). For an empty subclass the
  # new class shares the superclass's vtable (size == ssize == __vtable_size); also copy the superclass's
  # @instance_size (slot 1) and @name (slot 2). Only matches a literal `Class` receiver; dynamic forms left alone.
  # Objects created via `Class.new { ... }` / `Module.new { ... }` get their block's attr ivars resolved
  # against the Object (global) scope at compile time -- the block is a proc with no class scope of its own,
  # so `@foo` falls back to the global namespace (see EigenclassScope/ClassScope ivar resolution). Those
  # ivars are only discovered when the proc body compiles (in output_functions), which is AFTER Object's
  # @instance_size slot is emitted (compile_class), so Object's runtime instance_size -- and any anon class
  # that copies it -- stays too small and the setter's ivar write overflows the object's heap slot (exit-time
  # heap corruption). Pre-register each block's attr ivars into the Object scope here, during preprocess and
  # BEFORE the instance_size is emitted, so the compile-time count already includes them. Registration only
  # (add_ivar); the getter/setter methods themselves are still expanded by expand_attr_defs/class_eval.
  def register_dynamic_block_ivars(exp)
    return if !@global_scope
    obj = @global_scope.class_scope
    return if !obj
    exp.depth_first do |e|
      if e.is_a?(Array) && e[0] == :callm && (e[1] == :Class || e[1] == :Module) &&
         e[2] == :new && e[4].is_a?(Array) && e[4][0] == :proc && e[4][2].is_a?(Array)
        e[4][2].each do |st|
          next if !st.is_a?(Array)
          next if !(st[0] == :call && (st[1] == :attr_reader || st[1] == :attr_writer || st[1] == :attr_accessor))
          arr = st[2].is_a?(Array) ? st[2] : [st[2]]
          arr.each do |entry|
            es = entry.to_s
            nm = (es[0] == ?: ? es[1..-1] : es)
            next if nm.empty?
            obj.add_ivar("@#{nm}".to_sym)
          end
        end
      end
      :next
    end
  end

  # Expand attr_reader/attr_accessor/attr_writer calls within `node` (a Class.new/Module.new block) into
  # getter/setter :defm nodes, mirroring build_class_scopes for real class bodies. Only bare-symbol args
  # (to_s begins with ':') are expanded; other arg forms fall through to the runtime attr_* stub.
  def expand_attr_defs(node)
    node.depth_first do |be|
      if be.is_a?(Array) && be[0] == :call &&
         (be[1] == :attr_reader || be[1] == :attr_accessor || be[1] == :attr_writer)
        type = be[1]
        syms = be[2].is_a?(Array) ? be[2] : [be[2]]
        be.replace(E[:do])
        syms.each do |sym|
          s = sym.to_s
          # attr names may be given as symbols (`:a`, whose to_s is ":a") OR strings (`"b"`, whose to_s
          # is "b" -- MRI accepts both). Strip a leading ':' for the symbol form; use a string arg as-is.
          # (Previously non-':' args were skipped, silently dropping string names.)
          mn = (s[0] == ?: ? s[1..-1] : s).to_sym
          next if mn.to_s.empty?
          if type == :attr_reader || type == :attr_accessor
            be << E[:defm, mn, [], ["@#{mn}".to_sym]]
          end
          if type == :attr_writer || type == :attr_accessor
            be << E[:defm, "#{mn}=".to_sym, [:value], [[:assign, "@#{mn}".to_sym, :value]]]
          end
        end
      end
      :next
    end
  end

  # Class/module *instance* variables. A `@x` written DIRECTLY in a class/module body (not inside an
  # instance method) belongs to the class object, and the class's singleton methods (`def self.x`) already
  # read it from the global __classivar__<Class>__<x> (see EigenclassScope#get_instance_var). But the class
  # body resolves @x through ClassScope#get_instance_var as an INSTANCE-slot offset, so `@x = 0` in the body
  # and `@x` in a `def self.` read different storage (the class-body write is lost -> reads nil). Rewrite
  # only the DIRECT body @ivars to the same global; instance-method (:defm) and nested class/module bodies
  # are left untouched so their @ivars keep instance semantics.
  def rewrite_class_ivars(exp, prefix = "")
    return if !exp.is_a?(Array)
    if (exp[0] == :class || exp[0] == :module) && exp[1].is_a?(Symbol)
      # Accumulate the nesting path so the global name matches EigenclassScope's prefix (which is built from
      # the @next scope chain), e.g. `module ModuleSpecs; module Nesting; @tests` -> ModuleSpecs__Nesting.
      cname = prefix.empty? ? exp[1].to_s : "#{prefix}__#{exp[1]}"
      first = exp[0] == :class ? 3 : 2
      i = first
      while i < exp.length
        rewrite_direct_ivars(exp[i], cname)   # rewrite this body statement's DIRECT @ivars (skips nested scopes)
        rewrite_class_ivars(exp[i], cname)    # recurse into nested class/module bodies with the new prefix
        i += 1
      end
    else
      exp.each { |c| rewrite_class_ivars(c, prefix) }
    end
  end

  def rewrite_direct_ivars(node, cname)
    return if !node.is_a?(Array)
    # Do not descend into a nested scope -- its @ivars have their own (instance / inner-class) meaning.
    return if node[0] == :defm || node[0] == :defs || node[0] == :class || node[0] == :module
    i = 0
    while i < node.length
      child = node[i]
      if child.is_a?(Symbol) && child.to_s[0] == ?@ && child.to_s[1] != ?@
        gname = "__classivar__#{cname}__#{child.to_s[1..-1]}".to_sym
        @global_scope.add_global(gname) if @global_scope   # register so output_global_init nil-inits it
        # Emit the bare global-storage symbol (not a resolved [:global,...] node): get_arg maps it to the
        # global in read AND assignment-target position, whereas a pre-resolved node is rejected as an lvalue.
        node[i] = gname
      elsif child.is_a?(Array)
        rewrite_direct_ivars(child, cname)
      end
      i += 1
    end
  end

  def rewrite_class_new(exp)
    exp.depth_first do |e|
      if e.is_a?(Array) && e[0] == :callm && (e[1] == :Class || e[1] == :Module) && e[2] == :new
        args = e[3]
        # Normalize the argument shape BEFORE inspecting it (mirrors compile_callm): a single
        # paren-less argument arrives as a bare node, not a one-element list -- `Class.new sup do..end`
        # parses to args == :sup, and an expression superclass to an unwrapped [:callm,...]/keyword
        # node. Without this the args.is_a?(Array) test below silently dropped the superclass and
        # based the anonymous class on Object (wrong ancestry, wrong metaclass, lost methods).
        if args && !args.is_a?(Array)
          args = [args]
        elsif e[4] && args.is_a?(Array) && args.length > 1 && args[0].is_a?(Symbol) &&
              (@@keywords.include?(args[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(args[0]))
          args = [args]
        end
        # Class.new(sup) takes an optional superclass; Module.new takes none (modules do not inherit) --
        # base an anonymous module on Object so it has a valid layout, and rely on the block for its methods.
        if e[1] == :Class && args.is_a?(Array) && args.length > 0
          sup = args[0]
          validate_sup = true
        else
          sup = :Object
          validate_sup = false
        end
        # classob (slot 0, the metaclass) = the superclass's metaclass, NOT a bare `Class`, so the new class
        # inherits the superclass's CLASS methods (e.g. Proc's custom `def self.new` that captures the block;
        # with a bare Class metaclass, `sub.new {..}` dispatched to plain Class#new, dropping the block and
        # leaving @addr nil -> the resulting proc segfaulted on call).
        # A block (e[4]) carries method/attr/include definitions for the anonymous class. Evaluate it with
        # self bound to the new class via class_eval, so its `def`s (which emit __set_vtable(self,...)),
        # define_method calls, and self-relative calls register on the new class. Each low-level slot op is
        # individually :sexp-wrapped (they are raw primitives), but the :let and the class_eval callm are
        # ordinary nodes so rewrite_lambda still converts the block into a proc.
        block = e[4]
        # Expand attr_reader/accessor/writer inside the block into getter/setter defms at COMPILE time
        # (mirrors build_class_scopes for class bodies). The runtime attr_* methods cannot build a getter --
        # there is no ivar-by-name access -- but a `def name; @name; end` defm inside the block compiles the
        # ivar to its slot and registers fine when the block runs via class_eval. Only bare-symbol args are
        # handled (their to_s starts with ':'); string/expr args are left to the runtime stub.
        expand_attr_defs(block) if block.is_a?(Array)
        # The block's ivars (`@foo` in its defms/attr setters) resolve against the Object (global) scope at
        # compile time -- a proc has no class scope of its own. register_dynamic_block_ivars has already
        # assigned each block-attr ivar a stable Object-scope offset, so an instance must have at least
        # (max_offset + 1) slots or the setter's slot write overflows the object (exit-time heap corruption
        # -- the anon class only copies its superclass's @instance_size, which does not account for these
        # ivars). Compute the largest offset used by this block and, below, raise the new class's slot-1
        # @instance_size to cover it. Offsets only ever grow (append), so a value looked up now stays valid.
        needed_slots = 0
        if block.is_a?(Array) && @global_scope && @global_scope.class_scope
          obj = @global_scope.class_scope
          block.depth_first do |bx|
            bx.each do |n|
              next if !(n.is_a?(Symbol) && n.to_s[0] == ?@ && n.to_s[1] != ?@)
              off = obj.find_ivar_offset(n.to_sym)
              needed_slots = off + 1 if off && off + 1 > needed_slots
            end
          end
        end
        # Evaluate the superclass into a plain local FIRST (a normal :assign, not inside a :sexp). The
        # superclass can be a scoped constant `Foo::Bar` ([:deref,...]) or any expression; a :deref inside
        # a raw :sexp is emitted as a call to a nonexistent `deref` symbol (link error). Using the local
        # __sup in the low-level slot ops keeps them simple values.
        # `Class.new(sup)` with a non-Class superclass must raise TypeError, not crash. The low-level
        # build below does `(index __sup 0)` and copies vtable slots from __sup; if __sup is a tagged
        # immediate (e.g. `Class.new(1)`) that dereferences the tag as a pointer and segfaults. Guard with
        # a runtime is_a?(Class) check (safe on every value -- immediates return false without crashing).
        # Only when an explicit superclass was given (no-arg / Module.new use :Object, always valid).
        inner = E[:let, [:__tmpcls, :__sup],
          E[:assign, :__sup, sup]]
        if validate_sup
          inner << E[:if, E[:callm, :__sup, :is_a?, [:Class]], [:do],
            E[:raise, E[:callm, :TypeError, :new, ["superclass must be a Class"]]]]
        end
        inner << E[:sexp, E[:assign, :__tmpcls, E[:__new_class_object, :__vtable_size, :__sup, :__vtable_size, E[:index, :__sup, 0]]]]
        inner << E[:sexp, E[:assign, E[:index, :__tmpcls, 1], E[:index, :__sup, 1]]]
        inner << E[:sexp, E[:assign, E[:index, :__tmpcls, 2], E[:index, :__sup, 2]]]
        # Raise @instance_size (slot 1) to cover the block's ivars if the superclass's size is smaller, so
        # `new` allocates enough slots for the block-defined setters/ivars (see needed_slots above).
        if needed_slots > 0
          inner << E[:sexp, E[:if, E[:lt, E[:index, :__tmpcls, 1], needed_slots],
                             E[:assign, E[:index, :__tmpcls, 1], needed_slots]]]
        end
        if block
          inner << E[:callm, :__tmpcls, :class_eval, [], block]
        end
        inner << :__tmpcls
        e.replace(inner)
      end
      :next
    end
  end

  def rewrite_range(exp)
    exp.depth_first do |e|
      if e[0] == :range
        e.replace(E[:callm, :Range, :new, e[1..-1]])
      elsif e[0] == :exclusive_range
        # For exclusive range (...), pass true as the third argument. The args must be ONE list (the
        # callm's 4th element) -- passing e[1], e[2], true as separate callm elements made Range.new
        # receive only `min` ("wrong number of arguments (given 1, expected 2+)"), breaking every `...`.
        e.replace(E[:callm, :Range, :new, [e[1], e[2], true]])
      end
      :next
    end
  end

  def create_concat(sub)
    right = sub.pop
    right = E[:callm,right,:to_s]
    return right if sub.size == 0
    E[:callm, create_concat(sub), :concat, [right]]
  end

  def rewrite_concat(exp)
    exp.depth_first do |e|
      if e[0] == :concat
        e.replace(create_concat(e[1..-1]))
      end
      :next
    end
  end

  # build_class_scopes
  #
  # Consider the case where I open a class, define a method that refers to an as yet undefined
  # class. Then later I re-open the class and defines the earlier class as an inner class:
  #
  #     class Foo
  #         def hello
  #            Bar.new
  #         end
  #     end
  #
  #     class Foo
  #        class Bar
  #        end
  #     end
  #
  # To handle this case, <tt>ClassScope</tt> objects must persist across open/close of a class,
  # and they do. However, to compile this to static references, I also must identify any references
  # and resolve them, to be able to distinguish a possible ::Bar from ::Foo::Bar
  #
  # (we still need to be able to fall back to dynamic constant lookup)
  #
  # Hoist `require`d file content to the program top level. `require` (see Parser#require) inlines a
  # file's parsed AST as a `[:required, <ast>]` node AT the require's lexical position. When the require
  # sits inside a block/proc -- e.g. rubyspec's `before :each do require "stringio" end` -- the file's
  # `class`/`module` definitions end up nested inside a block, where the compiler mis-builds them: a class
  # defined in a block gets a garbage @instance_size and is not properly created (`undefined method 'new'`;
  # under-sized instance -> initializer writes ivars out of bounds -> heap corruption). In Ruby `require`
  # loads at the top level regardless of where it runs, so moving the definitions to the top level is both
  # the fix and the correct semantics; the require expression itself is left behind as `true` (its return
  # value). Only real `[:required, ast]` nodes are hoisted -- a `[:required, [:require_missing, q]]` marker
  # is left in place so a missing-file require inside a method/block still becomes a runtime LoadError
  # (compile_required decides that from scope), not a top-level build error.
  def hoist_requires(exp)
    return if !exp.is_a?(Array) || exp[0] != :do
    hoisted = []
    hoist_from = lambda do |node|
      return if !node.is_a?(Array)
      node.each_index do |i|
        c = node[i]
        next if !c.is_a?(Array)
        if c[0] == :required
          # Do not descend into required content (that is the file's own top level). Hoist a real
          # require; leave a require_missing marker where it is.
          if !(c[1].is_a?(Array) && c[1][0] == :require_missing)
            hoisted << c
            node[i] = true
          end
        else
          hoist_from.call(c)
        end
      end
    end
    # A require that is itself a direct top-level statement is already at the top level -- leave it.
    # Requires nested anywhere inside a top-level statement's subtree are hoisted.
    i = 1
    while i < exp.length
      c = exp[i]
      hoist_from.call(c) if c.is_a?(Array) && c[0] != :required
      i += 1
    end
    # Insert the hoisted requires AFTER the last existing top-level require (the injected core/library
    # requires), so the hoisted file's classes -- which depend on core (String, Integer, ...) -- still
    # load after core, but before the user code that references them.
    if !hoisted.empty?
      pos = 1
      j = 1
      while j < exp.length
        pos = j + 1 if exp[j].is_a?(Array) && exp[j][0] == :required
        j += 1
      end
      exp.insert(pos, *hoisted)
    end
  end

  def build_class_scopes(exps, scope)
    return if !exps.is_a?(Array)

    exps.each do |e|
      if e.is_a?(Array)
        if e[0] == :defm && scope.is_a?(ModuleScope)
          scope.add_vtable_entry(e[1]) # add method into vtable of class-scope to associate with class

          e[3].depth_first do |exp|
            exp.each do |n|
              scope.add_ivar(n) if n.is_a?(Symbol) and n.to_s[0] == ?@ && n.to_s[1] != ?@
            end
          end

        elsif e[0] == :call && (e[1] == :attr_accessor || e[1] == :attr_reader || e[1] == :attr_writer)
          # This is a bit presumptious, assuming noone are stupid enough to overload
          # attr_accessor, attr_reader without making them do more or less the same thing.
          # but the right thing to do is actually to call the method.
          #
          # In any case there is no actual harm in allocating the vtable
          # entry.`
          #
          arr = e[2].is_a?(Array) ? e[2] : [e[2]]
          # attr names may be symbols (`:a`, to_s ":a") or strings (`"b"`, to_s "b"). Strip a leading ':'
          # for the symbol form; use a string as-is. `entry.to_s[1..-1]` unconditionally dropped the first
          # char, so a string name like "b" became "" -> an empty getter/setter (undefined `b`/`b=`).
          # (Inlined rather than a shared lambda: a captured closure called inside these .each blocks
          # breaks the self-hosted compiler.)
          # Only add vtable entries if we're in a class/module scope
          # At global scope, attr_accessor applies to Object
          target_scope = scope.is_a?(ModuleScope) ? scope : scope.class_scope
          arr.each {|entry|
            es = entry.to_s
            nm = (es[0] == ?: ? es[1..-1] : es)
            next if nm.empty?
            target_scope.add_vtable_entry(nm.to_sym)
            target_scope.add_ivar("@#{nm}".to_sym)
          }

          # Then let's do the quick hack:
          #

          type = e[1]
          syms = e[2]

          e.replace(E[:do])
          syms.each do |mname|
            ms = mname.to_s
            nm = (ms[0] == ?: ? ms[1..-1] : ms)
            next if nm.empty?
            mname = nm.to_sym
            if (type == :attr_reader || type == :attr_accessor)
              e << E[:defm, mname, [], ["@#{mname}".to_sym]]
            end
            if (type == :attr_writer || type == :attr_accessor)
              e << E[:defm, "#{mname}=".to_sym, [:value], [[:assign, "@#{mname}".to_sym, :value]]]
            end
          end
        elsif e[0] == :class
          # FIXME: While splitting this out is a reasonable
          # refactoring step; it was done as a workaround for a compiler @bug
          build_class_scopes_for_class(e, scope)
        elsif e[0] == :module
          # Handle nested module syntax: module Foo::Bar
          module_name = e[1]
          parent_scope = scope

          # Handle global namespace module definition like [:global, :A]
          # For module ::A, create the module in global scope regardless of current scope
          if module_name.is_a?(Array) && module_name[0] == :global
            module_name = module_name[1]
            parent_scope = @global_scope
          elsif module_name.is_a?(Array) && module_name[0] == :deref
            # Flatten Foo::Bar -- and deeper, Foo::Bar::Baz -- to Foo__Bar__Baz. The previous
            # one-level "#{module_name[1]}__#{module_name[2]}" produced a malformed name for 3+
            # levels because module_name[1] was itself a [:deref, ...] node.
            module_name = flatten_deref(module_name)
          end

          cscope   = @classes[module_name.to_sym]
          cscope ||= ModuleScope.new(parent_scope, module_name, @vtableoffsets, @classes[:Object])
          @classes[cscope.name.to_sym] =  cscope
          @global_scope.add_constant(cscope.name.to_sym,cscope)
          parent_scope.add_constant(module_name.to_sym,cscope)
          build_class_scopes(e[3], cscope)
        elsif e[0] == :sexp
        else
          (e[1..-1] || []).each do |x|
            build_class_scopes(x,scope)
          end
        end
      end
    end
  end

  def build_class_scopes_for_class(e, scope)
    superclass = e[2]
    # Handle superclass - it can be a symbol, constant name, or an expression
    # For expressions (like method calls), we can't resolve at compile time
    # so we fall back to Object as the known superclass
    if superclass.is_a?(Symbol)
      superc = @classes[superclass]
      # If not found and we're inside a module/class scope, try qualified name
      if !superc && scope.respond_to?(:name) && !scope.name.empty?
        superc = @classes["#{scope.name}__#{superclass}".to_sym]
      end
    elsif superclass.is_a?(Array) && superclass[0] == :deref
      # Handle namespaced superclass like Foo::Bar
      # For now just use Object as fallback
      superc = @classes[:Object]
    else
      # Dynamic superclass expression - use Object as compile-time fallback
      superc = @classes[:Object]
    end
    name = e[1]

    # Handle global namespace class definition like [:global, :A]
    # For class ::A, create the class in global scope regardless of current scope
    if name.is_a?(Array) && name[0] == :global
      name = name[1]
      scope = @global_scope
    # Handle namespaced class names like [:deref, :Foo, :Bar]
    # For class Foo::Bar, we need to find Foo's scope and create Bar within it
    elsif name.is_a?(Array) && name[0] == :deref
      # Extract parent and child from [:deref, parent, child]
      # For Foo::Bar::Baz, this will be nested: [:deref, [:deref, :Foo, :Bar], :Baz]
      parent_name = name[1]
      child_name = name[2]

      # Recursively resolve parent scope
      if parent_name.is_a?(Array) && parent_name[0] == :deref
        # Nested namespace - need to resolve recursively
        # For now, convert to fully qualified name
        parts = []
        n = name
        while n.is_a?(Array) && n[0] == :deref
          parts.unshift(n[2])
          n = n[1]
        end
        parts.unshift(n) if n.is_a?(Symbol)

        # Build fully qualified name: Foo__Bar__Baz
        qualified_name = parts.join("__").to_sym
        name = qualified_name
        # Find the parent scope (everything except last part)
        parent_qualified = parts[0..-2].join("__").to_sym
        parent_scope = @classes[parent_qualified] || @global_scope
      else
        # Simple case: parent is a direct symbol like :Foo
        parent_scope = @classes[parent_name] || @global_scope
        # Fully qualified name is Parent__Child
        name = "#{parent_name}__#{child_name}".to_sym
      end

      scope = parent_scope
    elsif name.is_a?(Array) && name[0] == :eigen
      name = clean_method_name(name.to_s)
    end

    # A nested-constant name (Foo::Bar) may still be an unflattened [:deref, ...] node here for
    # some forms; flatten it to Foo__Bar so it can be used as a class-table key and symbol.
    if name.is_a?(Array) && name[0] == :deref
      parts = []
      n = name
      while n.is_a?(Array) && n[0] == :deref
        parts.unshift(n[2])
        n = n[1]
      end
      parts.unshift(n) if n.is_a?(Symbol)
      name = parts.join("__").to_sym
    end

    cscope = @classes[name.to_sym]
    cscope = ClassScope.new(scope, name, @vtableoffsets, superc) if !cscope
    @classes[cscope.name.to_sym] =  cscope
    @global_scope.add_constant(cscope.name.to_sym,cscope)
    scope.add_constant(name.to_sym,cscope) if scope != @global_scope
    build_class_scopes(e[3], cscope)
  end
          
  # Handle destructuring (e.g. a,b = [1,2])
  # by rewriting to
  #
  # (let (__destruct) (do
  #   (assign __destruct (array 1 2))
  #   (assign a (callm __destruct [] (0)))
  #   (assign b (callm __destruct [] (1)))
  # ))
  #
  # For splats (e.g. a, *b, c = [1,2,3,4]):
  # - Before splat: assign from index 0, 1, ...
  # - Splat: collect remaining elements minus those after it
  # - After splat: assign from end using negative indices
  #
  # Helper to flatten nested :comma nodes
  # [:comma, :a, [:comma, :b, :c]] => [:a, :b, :c]
  def flatten_comma(node)
    return [node] unless node.is_a?(Array) && node[0] == :comma
    result = []
    node[1..-1].each do |elem|
      result.concat(flatten_comma(elem))
    end
    result
  end

  # Build the assignment for one destructuring target. A plain lvalue (local, ivar, [:index, ...])
  # becomes `[:assign, target, value]`. But a call-form target -- `a[i]` / `a[*idx]` (a `:[]` getter)
  # or `obj.attr` -- must become a SETTER call `recv.meth=(args..., value)` HERE, not left as an
  # `[:assign, getter-callm, value]`. The parser already emits the setter for a single `a[i] = v`, but
  # multiple-assignment targets are parsed as plain getter-callms; leaving them for compile_assign works
  # for a bare index but NOT for a splat index (`a[*idx]`), because rewrite_splat_to_array runs first and
  # rewrites the getter-callm into a value-returning let-block, which is then an invalid assignment lhs.
  def destruct_target_assign(target, value)
    if target.is_a?(Array) && (target[0] == :callm || target[0] == :safe_callm) && !target[1].to_s.start_with?("__destruct")
      setter = (target[2].to_s + "=").to_sym
      args = target[3] || []
      args = [args] unless args.is_a?(Array)
      return E[:callm, target[1], setter, args + [value]]
    end
    E[:assign, target, value]
  end

  def rewrite_destruct(exps)
    # Handle single splat assignment: (*a) = [1, 2, 3] => a = [1, 2, 3]
    exps.depth_first(:assign) do |e|
      l = e[1]
      if l.is_a?(Array) && l[0] == :splat
        # Single splat on left side: (*var) = rhs
        # Convert to: var = [rhs elements...]
        var = l[1]
        r = e[2]
        # Wrap right side in array if it's not already an array literal
        e[1] = var
        if r.is_a?(Array) && r[0] == :array
          # Already an array literal (also how a bare comma tuple `1, 2` is represented) -- keep as is.
        elsif r.is_a?(Array)
          # A bare comma tuple of values (`b, c`) splats element-wise; a SINGLE structured node
          # (`*x` -> [:splat, x], `foo.bar` -> [:callm, ...], `a + b` -> [:add, ...]) is ONE value and
          # must be wrapped whole. `[:array, *r]` on `[:splat, x]` would flatten it to
          # `[:array, :splat, x]` and mis-splat -> `*a = *x` then raised "wrong number of arguments".
          node_head = r[0].is_a?(Symbol) &&
            (Compiler::Keywords.include?(r[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(r[0]))
          e[2] = node_head ? [:array, r] : [:array, *r]
        else
          # Single value, wrap in array
          e[2] = [:array, r]
        end
      end
    end

    # Convert [:comma, ...] on LHS to [:destruct, ...]
    exps.depth_first(:assign) do |e|
      l = e[1]
      if l.is_a?(Array) && l[0] == :comma
        # Flatten nested :comma nodes and convert to [:destruct, a, b, c, ...]
        vars = flatten_comma(l)
        e[1] = [:destruct, *vars]
      end
    end

    # Now process [:destruct, ...] assignments
    exps.depth_first(:assign) do |e|
      l = e[1]
      if l.is_a?(Array) && l[0] == :destruct
        vars = l[1..-1]
        r = e[2]

        # Find splat index if present
        splat_idx = nil
        splat_var = nil
        vars.each_with_index do |v, i|
          if v.is_a?(Array) && v[0] == :splat
            splat_idx = i
            splat_var = v[1]
            break
          end
        end

        # Each expansion gets a UNIQUE temp name: a nested grouped target (`((a, b), c) = ...`)
        # expands to a nested let whose initializer reads the OUTER expansion's temp
        # (`inner = Array(outer[i])`). With a single shared name the inner `let (__destruct)`
        # shadowed the outer before the initializer read it, so the RHS read the freshly
        # allocated (uninitialized) inner slot -> garbage receiver -> SIGSEGV (deterministic
        # inside blocks; top level survived only by stack-slot-layout luck).
        @destruct_seq = (@destruct_seq || 0) + 1
        dtemp = "__destruct#{@destruct_seq}".to_sym
        e[0] = :let
        e[1] = [dtemp]
        # If RHS is a flat array (comma expression like `1, 2, 3`), wrap it in :array
        # Without this, `a, b, c = 1, 2, 3` passes 3 args to Array() instead of 1.
        # A single AST-operator node (e.g. [:callm, ...], [:array, ...], [:add, ...]) must NOT be
        # wrapped -- it is already one value. The old test `!r[0].is_a?(Symbol)` misfired when the
        # first comma element was a bare variable/global reference (e.g. `a, b = $foo, 5` parses to
        # [:"$foo", 5], whose head :"$foo" is a Symbol but NOT an operator), leaving it unwrapped and
        # miscompiled as the call `$foo(5)`. Distinguish by recognising real node tags: only heads that
        # are keywords or call forms mark a single node; any other symbol head is a comma tuple.
        # A sole splat RHS (`a, *b = *x`): node_head below treats [:splat, x] as a single node and skips
        # the wrapping, so `Array([:splat, x])` mis-splats x's elements into Array()'s argument list
        # ("wrong number of arguments"). Wrap it as the array literal `[*x]` so compile_array expands it
        # to x.to_a first. A comma tuple that merely CONTAINS a splat (`a, *b = 1, *x`) already has a
        # non-splat head and is wrapped by the branch below, so only the sole-splat case needs this.
        if r.is_a?(Array) && r[0] == :splat
          r = [:array, r]
        end
        node_head = r.is_a?(Array) && !r.empty? && r[0].is_a?(Symbol) &&
          (Compiler::Keywords.include?(r[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(r[0]))
        if r.is_a?(Array) && !r.empty? && !node_head
          r = [:array] + r
        end
        # Convert right-hand side to array using Array() for proper destructuring
        # Array() tries to_ary, then to_a, then wraps in array if neither exists
        # This handles cases like `x, y = 42` where 42 doesn't respond to to_a
        e[2] = [:do, [:assign, dtemp, [:call, :Array, [r]]]]
        ex = e

        if splat_idx
          # Handle destructuring with splat
          # Before splat: use positive indices
          (0...splat_idx).each do |i|
            v = vars[i]
            # If v is [:splat, anything], unwrap it - can't assign to splat directly
            # In nested destructuring, splat just means "assign the value"
            if v.is_a?(Array) && v[0] == :splat
              v = v[1]
            # If v is an array but not a known AST operator node, it's nested destructuring
            elsif v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
              v = [:destruct, *v]
            end
            ex[2] << destruct_target_assign(v, [:callm,dtemp,:[],[i]])
          end

          # After splat: use negative indices from the end
          after_splat = vars.length - splat_idx - 1
          if after_splat > 0
            (1..after_splat).each do |offset|
              idx = splat_idx + offset
              v = vars[idx]
              # If v is [:splat, var], unwrap it - can't assign to splat directly
              if v.is_a?(Array) && v[0] == :splat
                v = v[1]
              # If v is an array but not a known AST operator node, it's nested destructuring
              elsif v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
                v = [:destruct, *v]
              end
              # Use negative index: -1 for last element, -2 for second-to-last, etc
              neg_idx = -after_splat + offset - 1
              ex[2] << destruct_target_assign(v, [:callm,dtemp,:[],[neg_idx]])
            end
          end

          # Splat: collect remaining elements
          # For a,*b,c,d: start_idx=1, end_idx=-2 (skip last 2)
          # For a,b,*c: start_idx=2, end_idx=nil (to end)
          # For *a,b,c: start_idx=0, end_idx=-2 (skip last 2)
          start_idx = splat_idx
          if after_splat > 0
            # Use range form: __destruct[start_idx..-after_splat-1]
            # This handles splat in the middle or start with tail elements
            end_idx = -(after_splat + 1)
            # Range endpoints must be Integer OBJECTS (like the single-element `[i]` accesses above), not
            # raw `[:sexp, N]` ints: Array#[](range) -> __range_get calls `.first`/`.last`/`.__get_raw` on
            # the endpoints, which dereferences a raw int as an object pointer and SIGSEGVs.
            ex[2] << destruct_target_assign(splat_var,
              [:callm, dtemp, :[],
                [[:range, start_idx, end_idx]]])
          else
            # No elements after splat, use range to end: __destruct[start_idx..-1]. Endpoints are Integer
            # objects, not raw `[:sexp, N]` ints (see note above -- __range_get dereferences them as objects).
            ex[2] << destruct_target_assign(splat_var,
              [:callm, dtemp, :[],
                [[:range, start_idx, -1]]])
          end
        else
          # No splat: simple destructuring
          vars.each_with_index do |v,i|
            # If v is [:splat, var], unwrap it - can't assign to splat directly
            # In this context, splat just means "assign the value to var"
            if v.is_a?(Array) && v[0] == :splat
              v = v[1]
            # If v is an array but not a known AST operator node, it's nested destructuring
            # Wrap it in :destruct so it gets expanded recursively
            elsif v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
              v = [:destruct, *v]
            end
            ex[2] << destruct_target_assign(v, [:callm,dtemp,:[],[i]])
          end
        end
      end
    end
  end

  def rewrite_yield(exps)
    exps.depth_first(:yield) do |e|
      e[0] = [:call, :yield]
    end
  end

  # Transform for loops to .each iterators while returning the enumerable
  # for x in array; body; end => (__for_tmp = array; __for_tmp.each { |x| body }; __for_tmp)
  # This ensures the for loop returns the enumerable (Ruby semantics), not nil from .each
  def rewrite_for(exps)
    exps.depth_first(:for) do |e|
      # e = [:for, var, enumerable, [:do, exp1, exp2, ...]]
      var = e[1]
      enumerable = e[2]
      body = e[3]

      # Check if var is a complex expression (class var, instance var, constant, etc.)
      # If so, we need to use a temporary parameter and assign to the actual target
      if var.is_a?(Array) || (var.is_a?(Symbol) && (var.to_s.start_with?('@@', '@') || var.to_s[0] == var.to_s[0].upcase))
        # Complex target - use temporary parameter
        tmp_param = :__for_var
        body_exps = (body.is_a?(Array) && body[0] == :do) ? body[1..-1] : [body]
        # Prepend assignment of tmp_param to actual var at start of body
        body_exps = [[:assign, var, tmp_param]] + body_exps
        proc_node = E[e.position, :proc, [tmp_param], body_exps, nil, nil]
      else
        # Simple variable - use it directly as parameter
        body_exps = (body.is_a?(Array) && body[0] == :do) ? body[1..-1] : [body]
        proc_node = E[e.position, :proc, [var], body_exps, nil, nil]
      end

      # Modify e in-place to become [:let, [__for_tmp], [:do, assign, each_call, return_tmp]]
      # This creates: (__for_tmp = enumerable; __for_tmp.each { |var| body }; __for_tmp)
      # Using :let ensures __for_tmp is scoped to this expression
      e[0] = :let
      e[1] = [:__for_tmp]
      e[2] = [:do,
        [:assign, :__for_tmp, enumerable],
        [:callm, :__for_tmp, :each, [], proc_node],
        :__for_tmp
      ]
      # Remove old elements
      e.slice!(3..-1) if e.length > 3

      :skip  # Don't reprocess the transformed node
    end
  end

  def setup_global_scope(exp)
    if !@global_scope
      @global_scope = GlobalScope.new(@vtableoffsets)
      build_class_scopes(exp,@global_scope)
    end
  end

  # Pre-register constants defined in class bodies (including inside lambdas/procs)
  # This ensures constants are visible to code that comes after them in the class body
  def register_constants(exp, scope)
    exp.depth_first(:class) do |class_node|
      # Find the ClassScope for this class
      class_name = class_node[1]

      # Handle global namespace (::ClassName)
      if class_name.is_a?(Array) && class_name[0] == :global
        class_name = class_name[1]
      end

      # Handle nested classes (Foo::Bar)
      if class_name.is_a?(Array) && class_name[0] == :deref
        class_name = flatten_deref(class_name)
      end

      class_scope = @classes[class_name]
      next unless class_scope  # Skip if scope wasn't created

      # Scan class body for constant assignments (including in lambdas/procs)
      class_node[3..-1].each do |stmt|
        next unless stmt.is_a?(Array)
        stmt.depth_first(:assign) do |assign_node|
          left = assign_node[1]
          if left.is_a?(Symbol) && (?A..?Z).member?(left.to_s[0])
            # Add to ClassScope so get_constant can find it
            class_scope.add_constant(left)
            # Add to global constants for .bss emission
            prefix = class_scope.name
            full_name = prefix.empty? ? left : "#{prefix}__#{left}".to_sym
            @global_constants << full_name
          end
        end
      end

      :skip  # Don't recurse into nested classes (they're handled separately)
    end
  end

  # Helper to flatten Foo::Bar::Baz to Foo__Bar__Baz
  def flatten_deref(node)
    parts = []
    n = node
    while n.is_a?(Array) && n[0] == :deref && n.length == 3
      if n[2].is_a?(Symbol)
        parts.unshift(n[2])
        n = n[1]
      else
        break
      end
    end
    if n.is_a?(Symbol)
      parts.unshift(n)
      parts.join("__").to_sym
    else
      node
    end
  end

  # Bare `super` (no parens) forwards the enclosing method's arguments; the parser emits it as the bare
  # symbol :super, which otherwise compiles to self.super() with NO args. `super()`/`super(x)` are already
  # [:call,:super,...] nodes and are left untouched. Build the forwarded-argument list from a method's
  # formal params: a simple/`=default` param forwards by name (its current value); `*rest` forwards as a
  # splat; a `&block` forwards implicitly (blocks are already forwarded), and keyword params are left for
  # a later pass. See memory bare-super-does-not-forward-args.
  def bare_super_fwd(params)
    fwd = []
    (params || []).each do |p|
      if p.is_a?(Symbol)
        fwd << p
      elsif p.is_a?(Array)
        nm = p[0]
        kind = p[1]
        if kind == :rest
          fwd << E[:splat, nm]
        elsif kind == :key || kind == :keyreq
          # Forward the keyword's CURRENT binding as a call-site pair (same shape
          # convert_ternalt_in_calls emits; group_keyword_arguments -- which runs
          # after this pass -- folds it into the trailing kwargs hash).
          fwd << E[:pair, E[:sexp, nm.inspect.to_sym], nm]
        elsif kind == :keyrest
          fwd << E[:hash_splat, nm]
        elsif kind == :block
          # block forwards implicitly
        else
          fwd << nm   # [:name, :default, expr] and any other positional -> forward by name
        end
      end
    end
    fwd
  end

  # Replace every BARE :super in a method body with a call that forwards `fwd`. Descends into blocks
  # (a block inherits the enclosing method's super) but stops at a nested :defm/:defun (its own params,
  # rewritten when depth_first visits it). Leaves the :super method-name of an explicit [:call,:super,...].
  def replace_bare_super(node, fwd)
    return if !node.is_a?(Array)
    return if node[0] == :defm || node[0] == :defun
    node.each_index do |i|
      child = node[i]
      if child == :super
        next if node[0] == :call && i == 1
        node[i] = E[:call, :super, fwd.map { |a| a.is_a?(Array) ? a.dup : a }]
      elsif child.is_a?(Array)
        replace_bare_super(child, fwd)
      end
    end
  end

  # Parenthesized (destructuring) block parameters: `{ |(a, b)| ... }` parses
  # the group as a [:destruct, a, b] PARAM, which nothing binds (reads compiled
  # as method calls). Replace each with a synthetic positional param and
  # prepend `a, b = __destruct_argN` to the body; rewrite_destruct (which runs
  # right after this pass) expands it through the normal masgn machinery,
  # including nested groups.
  # module_function support. Two parse shapes inside a module body:
  #  - BARE `module_function` swallows the FOLLOWING defms as its paren-less
  #    argument: [:module_function, <defm>] -- unwrap them back into the body
  #    and mark everything from there on.
  #  - `module_function :name, ...` is a normal [:call, :module_function, args].
  # For each marked instance method, a DUPLICATED `def self.name` (deep-copied
  # subtree -- later passes mutate in place) is appended to the module body, so
  # the method is callable both as an instance method (for include) and
  # directly on the module (MRI copies to the singleton class).
  def __deep_dup_node(n)
    return n if !n.is_a?(Array)
    out = E[]
    i = 0
    while i < n.length
      out << __deep_dup_node(n[i])
      i += 1
    end
    out
  end

  def rewrite_module_function(exp)
    exp.depth_first(:module) do |mod|
      body = mod[3]
      next if !body.is_a?(Array)
      # Body can be a single statement node or a list; normalize view
      stmts = body
      if body[0].is_a?(Symbol)
        # single-statement body: wrap AND write the wrapper back so element
        # replacements/appends are visible in the tree
        stmts = E[body]
        mod[3] = stmts
      end
      mode_from = nil
      named = {}
      newstmts = E[]
      i = 0
      while i < stmts.length
        st = stmts[i]
        i += 1
        if st.is_a?(Array) && st[0] == :module_function
          # Bare form: the paren-less call swallowed the FOLLOWING defm(s) as
          # its argument -- either one defm node or a LIST of nodes. Splice
          # them all back as body statements.
          mode_from = newstmts.length if mode_from.nil?
          # the swallowed nodes are st's elements from index 1 onward
          k = 1
          while k < st.length
            newstmts << st[k]
            k += 1
          end
        elsif st.is_a?(Array) && st[0] == :call && st[1] == :module_function
          args = st[2]
          if args.is_a?(Array) && args.length > 0
            args.each do |a|
              if a.is_a?(Symbol)
                nm = a.to_s
                nm = nm[1 .. -1] if nm[0] == ?:
                named[nm.to_sym] = true
              end
            end
          else
            mode_from = newstmts.length if mode_from.nil?
          end
        else
          newstmts << st
        end
      end
      stmts.replace(newstmts)
      next if mode_from.nil? && named.empty?
      extra = []
      i = 0
      while i < stmts.length
        st = stmts[i]
        if st.is_a?(Array) && st[0] == :defm && st[1].is_a?(Symbol)
          want = false
          want = true if !mode_from.nil? && i >= mode_from
          want = true if named[st[1]]
          if want
            extra << E[:defm, E[:self, st[1]], __deep_dup_node(st[2]), __deep_dup_node(st[3])]
          end
        end
        i += 1
      end
      extra.each { |d| stmts << d }
    end
    exp
  end

  def rewrite_destruct_block_params(exp)
    count = 0
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if (e[0] == :proc || e[0] == :lambda) && e[1].is_a?(Array)
        params = e[1]
        pre = []
        pi = 0
        while pi < params.length
          p = params[pi]
          if p.is_a?(Array) && p[0] == :destruct
            tmp = ("__destruct_arg" + count.to_s).to_sym
            count += 1
            pre << E[:assign, p, tmp]
            params[pi] = tmp
          end
          pi += 1
        end
        if pre.length > 0 && e[2]
          body = e[2]
          if body.is_a?(Array) && (body.empty? || body[0].is_a?(Array))
            e[2] = pre + body
          else
            e[2] = pre + [body]
          end
        end
      end
    end
    exp
  end

  def rewrite_bare_super(exp)
    exp.depth_first(:defm) do |e|
      replace_bare_super(e[3], bare_super_fwd(e[2]))
    end
    exp
  end

  # R1 (docs/review/refactoring.md): canonicalize the defm/proc/lambda BODY shape ONCE,
  # before any other pass runs. `def ... rescue/ensure ... end` (and block/lambda bodies
  # with rescue/ensure) parse to the BARE node [:block, args, stmts, rescue?, ensure?]
  # sitting alone in the body slot instead of a statement list. Downstream passes iterate
  # bodies as statement lists, and three of them historically mishandled or locally
  # re-wrapped the bare shape (the __wrapenv 32-file COMPILE_FAIL regression; the
  # default-arg+ensure runtime crash in rewrite_default_args). Wrap the bare node as a
  # one-statement list here so a body is ALWAYS a statement list downstream.
  # The discriminator matches the proven per-pass compensations (which remain as
  # harmless wrap-if-bare guards for defm/proc nodes CONSTRUCTED by later rewrites):
  # a genuine bare block node has an Array args slot at [1]; a statement list whose
  # first statement is a variable named `block` does not.
  def normalize_body_shape(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      bodyi = nil
      if e[0] == :defm
        bodyi = 3
      elsif e[0] == :proc || e[0] == :lambda
        bodyi = 2
      end
      if bodyi
        body = e[bodyi]
        if body.is_a?(Array) && body[0] == :block && body[1].is_a?(Array)
          e[bodyi] = [body]
        end
      end
    end
  end

  def preprocess exp
    # Move `require`d file content to the top level BEFORE any scope/ivar analysis runs.
    hoist_requires(exp)

    # Canonicalize rescue/ensure body shapes before anything else inspects bodies.
    normalize_body_shape(exp)

    # The global scope is needed for some rewrites
    setup_global_scope(exp)

    rewrite_rescue_mod(exp)   # `expr rescue fallback` -> begin/rescue block. Was never wired in: the raw
                              # [:rescue, fallback, expr] modifier node miscompiled as a rescue clause ->
                              # crash. Must run BEFORE rewrite_destruct so `a, b = expr rescue [..]` still
                              # has its plain [:assign, [:comma..], rhs] shape for the assign-hoist below.
    rewrite_for(exp)
    rewrite_module_function(exp)        # module_function -> duplicated def self.x (before other body rewrites)
    rewrite_destruct_block_params(exp)  # |(a,b)| params -> synthetic arg + masgn (before rewrite_destruct)
    rewrite_destruct(exp)
    rewrite_bare_super(exp)   # expand bare `super` to forward the method's args (before splat/symbol rewrites)

    # Pre-register constants after for/destruct rewrites create assignments
    register_constants(exp, @global_scope)

    convert_ternalt_in_calls(exp)  # Convert :ternalt to :pair for method call keyword arguments
    group_keyword_arguments(exp)   # Group :pair and :hash_splat nodes into :hash
    rewrite_concat(exp)
    rewrite_range(exp)
    rewrite_class_ivars(exp)  # direct class/module-body @ivars -> __classivar__ globals (before class_new)
    register_dynamic_block_ivars(exp)  # grow Object scope for Class.new{} block attr ivars before class_new expands them
    rewrite_class_new(exp)
    rewrite_defined(exp)  # Must run before rewrite_strconst
    rewrite_strconst(exp)
    rewrite_integer_constant(exp)
    rewrite_alias_method(exp)   # must precede rewrite_symbol_constant (needs bare :sym args)
    rewrite_define_method(exp)  # ditto -- needs the bare :sym name + the :proc block
    rewrite_method_name_introspection(exp) # inserts :sym literals -- must precede rewrite_symbol_constant
    rewrite_symbol_constant(exp)
    rewrite_operators(exp)
    rewrite_yield(exp)
    rewrite_forward_args(exp)    # Must run before rewrite_keyword_args
    rewrite_keyword_args(exp)   # Must run before rewrite_default_args
    rewrite_default_args(exp)
    rewrite_safe_opassign(exp)   # nil-guard `recv&.m OP= v` before other assignment rewrites see it
    rewrite_index_opassign(exp)  # expand `recv[*idx] ||=/&&= v` before rewrite_splat_to_array mangles the lvalue
    rewrite_splat_to_array(exp)
    rewrite_block_given(exp)     # expand before env capture so __closure__ boxes per-context
    rewrite_let_env(exp)
  end

  # Expand `recv[*idx] ||= v` and `recv[*idx] &&= v` (and the `obj.attr` call-form equivalent) into an
  # explicit read-modify-write over cached temps. compile_or_assign/compile_and_assign read the lvalue as
  # a getter and then re-use it as a setter, which works for a bare index (`recv[i] ||= v`) because
  # compile_assign turns the getter-callm into a setter. But when the index carries a SPLAT the following
  # rewrite_splat_to_array rewrites the getter-callm into a value-returning let-block, which is no longer a
  # valid assignment lhs ("Expected an argument on left hand side of assignment"). Expanding here -- before
  # that pass -- caches the receiver and each index operand ONCE, then emits a getter read and, on the
  # short-circuit branch, an explicit setter call; both survive rewrite_splat_to_array (sole-splat getter ->
  # let-block; splat+value setter -> coerced-in-place). `+=` and friends are already expanded to `:[]=` by
  # the parser, so only :or_assign/:and_assign need this. Fixed temp names => nested index-splat op-assigns
  # (vanishingly rare) are unsupported.
  # `recv&.m OP= v` must short-circuit the ENTIRE read-modify-write to nil when recv is nil (MRI
  # semantics). The parser expands `recv&.m += v` into `assign (safe_callm recv m) ((safe_callm recv
  # m) + v)` (and ||=/&&= into :or_assign/:and_assign with a safe_callm target) with no guard, so the
  # getter short-circuited to nil and then `nil + v` ran unconditionally -> NoMethodError (and a crash
  # in accumulated spec state). Wrap the whole assignment in a receiver nil-check and de-safe the
  # inner accesses (they are inside the guard). The receiver is re-evaluated in the guard; the
  # parser's own op-assign expansion already re-evaluates it, so this adds nothing new for the
  # (typical, simple-variable) receivers.
  def rewrite_safe_opassign(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if (e[0] == :assign || e[0] == :or_assign || e[0] == :and_assign) &&
         e[1].is_a?(Array) && e[1][0] == :safe_callm
        recv = e[1][1]
        meth = e[1][2]
        target = E[:callm, recv, meth]
        rhs = e[2]
        if e[0] == :assign && rhs.is_a?(Array)
          rhs.depth_first do |g|
            if g.is_a?(Array) && g[0] == :safe_callm && g[1] == recv && g[2] == meth
              g[0] = :callm
            end
          end
        end
        inner = E[e[0], target, rhs]
        e.replace(E[:if, E[:callm, recv, :nil?], :nil, inner])
      end
    end
    exp
  end

  def rewrite_index_opassign(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      next unless e.is_a?(Array) && (e[0] == :or_assign || e[0] == :and_assign)
      left = e[1]
      next unless left.is_a?(Array) && (left[0] == :callm || left[0] == :safe_callm)
      args = left[3]
      # Bare index / attribute op-assign already works via compile_assign; only a splat index is broken.
      next unless args.is_a?(Array) && args.any? { |a| a.is_a?(Array) && a[0] == :splat }

      recv   = left[1]
      meth   = left[2]
      setter = (meth.to_s + "=").to_sym
      is_or  = (e[0] == :or_assign)
      v      = e[2]

      letvars  = [:__oa_r]
      body     = [E[:assign, :__oa_r, recv]]
      new_args = []
      args.each_with_index do |a, i|
        tmp = "__oa_a#{i}".to_sym
        letvars << tmp
        if a.is_a?(Array) && a[0] == :splat
          body << E[:assign, tmp, a[1]]
          new_args << E[:splat, tmp]
        else
          body << E[:assign, tmp, a]
          new_args << tmp
        end
      end
      letvars << :__oa_t
      body << E[:assign, :__oa_t, E[:callm, :__oa_r, meth, new_args]]
      write = E[:callm, :__oa_r, setter, new_args + [v]]
      body << (is_or ? E[:if, :__oa_t, :__oa_t, write] : E[:if, :__oa_t, write, :__oa_t])
      e.replace(E[:let, letvars, *body])
    end
  end

  # Coerce a calling-side splat operand to an Array: `obj.m(*x)` / `f(*x)` for a non-Array x reads x's
  # @len/buffer as garbage -> SIGSEGV (e.g. mspec `@object.send(*@method)` where @method is a Symbol). Only
  # the SOLE-splat case is handled (no fixed args), so evaluating the receiver then the coerced operand keeps
  # Ruby left-to-right order. The operand is coerced ONCE into a temp via __splat_to_a (a bare defun), so the
  # splat stack-manipulation never re-runs a method call mid-setup. :__copysplat (block/arg forwarding) and an
  # already-coerced :__splat_a are left alone.
  # A `[:splat, op]` arg whose operand still needs coercing to an Array (not a forwarding marker, and not
  # already wrapped in `op.__splat_to_a`).
  def coercible_splat?(a)
    a.is_a?(Array) && a[0] == :splat && a[1] != :__copysplat && a[1] != :__splat_a &&
      !(a[1].is_a?(Array) && a[1][0] == :callm && a[1][2] == :__splat_to_a)
  end

  def rewrite_splat_to_array(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if e.is_a?(Array) && (e[0] == :callm || e[0] == :call)
        ai = (e[0] == :callm) ? 3 : 2
        args = e[ai]
        if args.is_a?(Array) && args.length == 1 && args[0].is_a?(Array) && args[0][0] == :splat
          op = args[0][1]
          if op != :__copysplat && op != :__splat_a
            if e[0] == :callm
              newcall = E[:callm, :__splat_r, e[2], [E[:splat, :__splat_a]]]
              newcall << e[4] if e[4]
              e.replace(E[:let, [:__splat_r, :__splat_a],
                E[:assign, :__splat_r, e[1]],
                E[:assign, :__splat_a, E[:callm, op, :__splat_to_a]],
                newcall])
            else
              e.replace(E[:let, [:__splat_a],
                E[:assign, :__splat_a, E[:callm, op, :__splat_to_a]],
                E[:call, e[1], [E[:splat, :__splat_a]]]])
            end
          end
        elsif args.is_a?(Array) && args.length > 1 && args.any? { |a| coercible_splat?(a) }
          # Splat mixed with other args (`m(*x, 1, 2)`): the sole-splat path above does not apply, and the
          # raw splat push reads the operand's @len directly -- garbage / a wild `subl %esp` SIGSEGV for a
          # non-Array operand (e.g. a mock). Coerce each splat operand to an Array in place via __splat_to_a
          # (Array -> itself, otherwise [x]). Coercion stays at the operand's original position, so the
          # left-to-right evaluation order of the surrounding fixed args is preserved.
          args.each do |a|
            a[1] = E[:callm, a[1], :__splat_to_a] if coercible_splat?(a)
          end
        end
      end
      # Array literal with a splat element (`[1, *obj]`). compile_array lowers this to `Array[1, *obj]` at
      # COMPILE time -- after this pass -- so the splat operand never reaches the call handling above and
      # was left uncoerced: the eventual splat push read the operand's @len directly, a garbage count for a
      # non-Array (e.g. an mspec mock) -> wild `subl %esp` SIGSEGV. Coerce each splat operand to an Array in
      # place, exactly like the mixed-call case.
      if e.is_a?(Array) && e[0] == :array && e.length > 1 && e[1..-1].any? { |a| coercible_splat?(a) }
        (1...e.length).each do |i|
          e[i][1] = E[:callm, e[i][1], :__splat_to_a] if coercible_splat?(e[i])
        end
      end
      :next
    end
  end

  # Transform argument forwarding (...) into explicit parameter capture and forwarding
  # This turns:
  #   def foo(...)
  #     bar(...)
  #   end
  # Into:
  #   def foo(*__fwd_args__, **__fwd_kwargs__, &__fwd_block__)
  #     bar(*__fwd_args__, **__fwd_kwargs__, &__fwd_block__)
  #   end
  # `__method__` / `__callee__` resolve to the enclosing method's name at COMPILE time -- there
  # is no runtime frame introspection. Correct for __method__ even under aliasing (it reports
  # the ORIGINAL name, which is exactly the compile-time name); __callee__ should report the
  # aliased callee and is approximated with the same name. Blocks inside the method see the
  # enclosing method's name (Ruby semantics); nested defm subtrees are skipped -- depth_first
  # visits them with their own name. Bare uses outside any method stay unresolved and raise
  # (MRI returns nil there; only reachable from toplevel scripts).
  def rewrite_method_name_introspection(exp)
    exp.depth_first(:defm) do |e|
      name = e[1]
      name = name.last if name.is_a?(Array)
      next :next if !name.is_a?(Symbol)
      sym = (":" + name.to_s).to_sym
      __subst_method_name(e[3], sym)
      :next
    end
  end

  # Replace bare :__method__ / :__callee__ identifiers and their no-arg call forms with the
  # given symbol literal, in place, without descending into nested :defm subtrees.
  def __subst_method_name(n, sym)
    return if !n.is_a?(Array)
    i = 0
    while i < n.length
      c = n[i]
      if c == :__method__ || c == :__callee__
        n[i] = sym
      elsif c.is_a?(Array)
        if c[0] == :call && (c[1] == :__method__ || c[1] == :__callee__)
          n[i] = sym
        elsif c[0] != :defm
          __subst_method_name(c, sym)
        end
      end
      i += 1
    end
  end

  def rewrite_forward_args(exp)
    exp.depth_first(:defm) do |e|
      args = e[2]
      next unless args.is_a?(Array)

      # Check if this method uses argument forwarding
      has_forward_args = args.any? { |arg| arg.is_a?(Array) && arg[0] == :forward_args }
      next unless has_forward_args

      # Replace [:forward_args] with explicit parameters
      # Handle cases like def(x, ...) or def(...)
      new_args = []
      args.each do |arg|
        if arg.is_a?(Array) && arg[0] == :forward_args
          # Replace with: *__fwd_args__, &__fwd_block__ -- exactly the shape an explicit
          # `def m(*a, &b)` lowers to, so the whole thing rides the proven splat + block-param
          # machinery. No keyrest: kwargs are not generally supported, and the old
          # [:__fwd_kwargs__, :keyrest] param plus a [:hash, [:hash_splat, ...]] argument at the
          # forward site compiled to garbage -- `def m(...); super(...); end` inside a Class.new
          # block SIGSEGV'd (language/method_spec) and every forwarded call grew a spurious
          # trailing hash argument.
          new_args << [:__fwd_args__, :rest]
          new_args << [:__fwd_block__, :block]
        else
          new_args << arg
        end
      end

      e[2] = new_args

      # Transform forward_args in method calls within the body
      # Find all :call and :callm nodes with [:forward_args] argument
      body = e[3]
      next unless body.is_a?(Array)

      body.depth_first do |node|
        next unless node.is_a?(Array)
        next unless node[0] == :call || node[0] == :callm

        # Get argument list index (different for :call vs :callm)
        args_index = node[0] == :call ? 2 : 3
        call_args = node[args_index]
        next unless call_args.is_a?(Array)

        # Replace :forward_args with splat forwarding
        if call_args.include?(:forward_args)
          # Replace [:forward_args] with proper forwarding:
          # *__fwd_args__ => [:splat, :__fwd_args__]
          # **__fwd_kwargs__ => [:hash, [:hash_splat, :__fwd_kwargs__]]
          # &__fwd_block__ => handled via block parameter, not in args
          new_call_args = call_args.map do |arg|
            if arg == :forward_args
              # Forward positionals and the block: `f(...)` -> `f(*__fwd_args__, &__fwd_block__)`.
              # [:to_block, ...] is the canonical &-forwarding argument shape (see the explicit
              # `q(*a, &b)` parse); compile_callm/compile_call pop it into the block slot, and a
              # nil __fwd_block__ correctly means "no block". The old form dropped the block
              # entirely and passed a bogus kwargs hash instead.
              [[:splat, :__fwd_args__], [:to_block, :__fwd_block__]]
            else
              arg
            end
          end.flatten(1)  # Flatten one level to merge the arrays

          node[args_index] = new_call_args
        end
      end
    end
  end

  # Transform keyword arguments from method signature into hash extraction
  # This turns:
  #   def foo(a:, b: default_val)
  #     body
  #   end
  # Into:
  #   def foo(__kwargs)
  #     a = __kwargs[:a] || raise(ArgumentError.new("missing keyword: :a"))
  #     b = __kwargs[:b] || default_val
  #     body
  #   end
  #
  # This must run BEFORE rewrite_default_args and rewrite_let_env
  def rewrite_keyword_args(exp)
    # Applies to methods (:defm, params at e[2]/body e[3]) AND blocks/lambdas (:proc, params e[1]/body e[2]).
    # Blocks were previously skipped, so a block keyword-rest param like `{ |a, **k| }` never had its kwargs
    # extracted: `k` was bound to a raw positional slot (a garbage count) instead of a Hash, and using it as
    # a Hash later (`k.is_a?(Hash)` / iterating it) dereferenced a bogus pointer -> SIGSEGV (block_spec).
    exp.depth_first(:defm, :proc) do |e|
      argi = e[0] == :defm ? 2 : 1
      bodyi = argi + 1
      args = e[argi]
      next unless args.is_a?(Array)

      # Skip methods with forwarding parameters (rewrite_forward_args handles these)
      has_forwarding = args.any? { |arg| arg.is_a?(Array) && (arg[0] == :__fwd_args__ || arg[0] == :__fwd_kwargs__ || arg[0] == :__fwd_block__) }
      next if has_forwarding

      # Check if any args are keyword arguments
      has_kwargs = args.any? { |arg| arg.is_a?(Array) && [:keyreq, :key, :keyrest].include?(arg[1]) }
      next unless has_kwargs

      # Collect regular args and keyword args
      regular_args = []
      kwarg_extractions = []
      has_keyrest = false
      keyrest_name = nil

      args.each do |arg|
        if arg.is_a?(Array)
          name = arg[0]
          type = arg[1]
          default = arg[2]

          if type == :keyreq
            # Required keyword argument
            kwarg_extractions << [:assign, name,
              [:or,
                [:callm, :__kwargs, :[], [[:sexp, name.inspect.to_sym]]],
                [:call, :raise, [[:callm, :ArgumentError, :new, ["missing keyword: :#{name}".to_sym]]]]
              ]
            ]
          elsif type == :key
            # Optional keyword argument with default
            kwarg_extractions << [:assign, name,
              [:or,
                [:callm, :__kwargs, :[], [[:sexp, name.inspect.to_sym]]],
                default
              ]
            ]
          elsif type == :keyrest
            # **kwargs - captures remaining keyword arguments
            has_keyrest = true
            keyrest_name = name
            # For now, just assign the whole hash
            kwarg_extractions << [:assign, name, :__kwargs] if name
          else
            # Regular argument
            regular_args << arg
          end
        else
          # Symbol argument (no type annotation)
          regular_args << arg
        end
      end

      body = e[bodyi]
      body = [] unless body.is_a?(Array)
      # A `def ... ensure/rescue ... end` body is ONE bare [:block, args, stmts, ...] node.
      # Keep it intact as a single statement: the `+ body` concatenations below otherwise
      # splice its ELEMENTS in as statements -- the :block tag became a bogus statement, the
      # ensure clause was silently dropped, and the mangled body defeated find_vars' capture
      # analysis (part of the __wrapenv COMPILE_FAIL regression).
      body = [body] if body[0] == :block && body[1].is_a?(Array)

      # If the method also has a splat (`*args`), __kwargs CANNOT be a trailing positional param: a
      # trailing param after a splat behaves like `*args, x` and steals the last positional (so
      # `m(*a, **kw); m(1,2)` gave a=[1], kw=2). Instead keep the splat greedy and pop a trailing Hash off
      # it into __kwargs at runtime (nil/non-Hash tail -> {}). Otherwise (no splat) __kwargs is an OPTIONAL
      # trailing positional defaulting to {} so the caller may omit all keyword args.
      rest_name = nil
      regular_args.each do |a|
        rest_name = a[0] if a.is_a?(Array) && a[1] == :rest
      end

      if rest_name
        new_args = regular_args
        pop_kwargs = [:assign, :__kwargs,
          [:if, [:callm, [:callm, rest_name, :last], :is_a?, [:Hash]],
            [:callm, rest_name, :pop],
            [:hash]]]
        # Declare __kwargs in a let (it is no longer a parameter in the splat case, so a bare assign would
        # not register it as a local and the extractions would read it as a method call).
        new_body = [[:let, [:__kwargs], pop_kwargs] + kwarg_extractions + body]
      else
        new_args = regular_args + [[:__kwargs, :default, [:hash]]]
        new_body = kwarg_extractions + body
      end

      # Update the definition
      e[argi] = new_args
      e[bodyi] = new_body
    end
  end

  # Transform default arguments from method signature into method body
  # This turns:
  #   def foo(a, b = expr)
  #     body
  #   end
  # Into:
  #   def foo(a, b)
  #     if numargs < 2; b = expr; end
  #     body
  #   end
  #
  # This must run BEFORE rewrite_let_env so that closures in default
  # expressions are properly handled.
  def rewrite_default_args(exp)
    exp.depth_first(:defm) do |e|
      args = e[2]
      if args
        if args.is_a?(Array)
          # Check for defaults
          has_defaults = false
          i = 0
          while i < args.length
            arg = args[i]
            if arg.is_a?(Array) && arg[1] == :default
              has_defaults = true
            end
            i = i + 1
          end

          if has_defaults
            # Count defaults
            default_count = 0
            ci = 0
            while ci < args.length
              carg = args[ci]
              if carg.is_a?(Array) && carg[1] == :default
                default_count = default_count + 1
              end
              ci = ci + 1
            end

            # Create arrays
            new_args = Array.new(args.length)
            default_assigns = Array.new(default_count)

            # Fill arrays
            di = 0
            i = 0
            while i < args.length
              arg = args[i]
              if arg.is_a?(Array) && arg[1] == :default
                name = arg[0]
                default_expr = arg[2]
                # Build if statement using different variable name
                threshold = i + 3
                cond = [:lt, :numargs, threshold]
                asgn = [:assign, name, default_expr]
                if_stmt = [:if, cond, asgn]
                default_assigns[di] = if_stmt
                di = di + 1
                new_args[i] = [name, :default, :nil]
              else
                new_args[i] = arg
              end
              i = i + 1
            end

            # Build new body with default assigns prepended
            body = e[3]
            body = [] if !body.is_a?(Array)

            new_body = []
            j = 0
            while j < default_count
              new_body << default_assigns[j]
              j = j + 1
            end
            k = 0
            while k < body.length
              new_body << body[k]
              k = k + 1
            end

            # Update the method definition
            e[2] = new_args
            e[3] = new_body
          end
        end
      end
    end
  end
end
