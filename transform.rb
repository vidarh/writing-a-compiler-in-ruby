
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
      if e[0] == :return
        e[0] = :preturn
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
      if e[0] == :lambda || e[0] == :proc
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

        # FIXME: Putting this inline further down appears to break.
        len = args.length

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

        e.replace(
          E[:do,
            [:assign, [:index, :__env__,0], [:stackframe]],
            [:assign, :__tmp_proc,
              [:defun, "__lambda_#{@e.get_local[1..-1]}",
                [:self,:__closure__,:__env__] + normalized_args,
                body
              ]
            ],
            # FIXME: Compiler bug: This works
            [:sexp, [:call, :__new_proc, [:__tmp_proc, :__env__, :self, len, :__closure__]]]
            # But this crashes:
            #E[exp.position,:sexp, E[:call, :__new_proc, E[:__tmp_proc, :__env__, :self, len]]]
          ]
        )
      end
    end
    return seen
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
        result = nil

        # Analyze the argument to determine its type
        if arg.is_a?(Array)
          case arg[0]
          # Assignment operators - all map to "assignment"
          when :assign, :massign, :iasgn, :op_asgn, :or_asgn, :and_asgn,
               :mul_assign, :div_assign, :mod_assign, :pow_assign,
               :and_bitwise_assign, :or_bitwise_assign, :xor_assign,
               :shl_assign, :shr_assign
            result = "assignment"
          # For other cases, return false
          else
            STDERR.puts "Warning: defined? for #{arg[0].inspect} not implemented, returning false"
            result = false
          end
        elsif arg.is_a?(Symbol)
          # For variables, return false for now
          STDERR.puts "Warning: defined? for variable #{arg.inspect} not implemented, returning false"
          result = false
        else
          STDERR.puts "Warning: defined? for #{arg.inspect} not implemented, returning false"
          result = false
        end

        # Replace the defined? node with the result
        # rewrite_strconst will handle string constant conversion
        if result == false
          e.replace(E[:false])
        else
          e.replace(E[result])
        end
      end
    end
  end

  # Re-write string constants outside %s() to
  # %s(call __get_string [original string constant])
  def rewrite_strconst(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
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
        name = v.to_s
        if v.is_a?(Symbol) && name[0] == ?:
          #STDERR.puts v.inspect
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
      v == :nil || v == :self ||
      v.to_s[0] == ?@ ||
      v == :true || v == :false  || v.to_s[0] < ?a
  end

  def push_var(scopes, env, v)
    sc = in_scopes(scopes,v)
    if sc.size == 0 && !env.member?(v) && !is_special_name?(v)
      scopes[-1] << v 
    end
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
    return [],env, false if !e
    e = [e] if !e.is_a?(Array)
    e.each do |n|
      if n.is_a?(Array)
        if n[0] == :assign
          vars1, env1 = find_vars(n[1],     scopes + [Set.new],env, freq, in_lambda, true, current_params)
          vars2, env2 = find_vars(n[2..-1], scopes + [Set.new],env, freq, in_lambda, false, current_params)
          env = env1 + env2
          vars = vars1+vars2
          vars.each {|v| push_var(scopes,env,v) if !is_special_name?(v) }
        elsif n[0] == :lambda || n[0] == :proc
          # Extract parameter names (handle arrays like [:param, default])
          params_raw = n[1] || []
          param_names = params_raw.is_a?(Array) ? params_raw.collect { |p| p.is_a?(Array) ? p[0] : p } : []
          param_scope = Set.new(param_names)
          # Pass a copy of param_scope as current_params to prevent it from being modified
          vars, env2= find_vars(n[2], scopes + [param_scope], env, freq, true, false, Set.new(param_names))

          # Clean out proc/lambda arguments from the %s(let ..) and the environment we're building
          vars  -= n[1] if n[1]
          # Don't remove params from env2 - if they're captured by nested lambdas,
          # they need to propagate up. The rewrite_env_vars will add initialization.
          env += env2

          n[2] = E[n.position,:let, vars, *n[2]] if n[2]
        else
          if    n[0] == :callm
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
            # Wrap receiver if it's an array (AST node) to prevent element-by-element iteration
            receiver = n[1].is_a?(Array) ? [n[1]] : n[1]
            vars, env = find_vars(receiver, scopes, env, freq, in_lambda, false, current_params)
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
    # return scopes[-1].to_a, env
  end

  def rewrite_env_vars(exp, env)
    seen = false
    exp.depth_first do |e|
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

        # Extract parameter names (handle tuples like [:param, :default, :nil])
        # Note: using .collect instead of .map (map doesn't exist in lib/core/array.rb)
        # param_list can be an array or a symbol like :block (for block arguments)
        params = param_list.is_a?(Array) ? param_list.collect { |p| p.is_a?(Array) ? p[0] : p } : []

        # Find which parameters are in env (need initialization)
        # Note: using reject with negation because .select doesn't exist in lib/core/array.rb
        captured_params = params.reject { |p| !env.include?(p) }

        # First, process the body to rewrite variable references
        if e[body_index]
          # FIXME: seen |= ... failed to compile
          if rewrite_env_vars(e[body_index], env)
            seen = true
          end
        end

        # Then insert initialization for captured parameters (after rewriting)
        # This way the RHS (parameter) won't be rewritten
        if !captured_params.empty? && e[body_index]
          # Note: using .collect instead of .map (map doesn't exist in lib/core/array.rb)
          param_inits = captured_params.collect do |p|
            idx = env.index(p)
            E[:assign, E[:index, :__env__, idx], p]
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
      if e.is_a?(Array) && e[0] == :call && e[1] == :yield
        seen = true
        args = e[2]
        e[0] = :callm
        e[1] = :__closure__
        e[2] = :call
        e[3] = args
      end

      e.each_with_index do |ex, i|
        # FIXME: This is necessary in order to avoid rewriting compiler keywords in some
        # circumstances. The proper solution would be to introduce more types of
        # expression nodes in the parser
        # Skip AST operator symbols at index 0 - they're not variable references
        next if i == 0 && (ex == :index || ex == :deref)
        # Also skip :callm at position 0
        next if i == 0 && ex == :callm
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
        num = env.index(ex)
        if num
          seen = true
          e[i] = E[:index, :__env__, num]
        end
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

  def rewrite_let_env(exp)
    exp.depth_first(:defm) do |e|
      args   = Set[*e[2].collect{|a| a.kind_of?(Array) ? a[0] : a}]

      # Count number of "regular" arguments (non "rest", non "block")
      # FIXME: There are cleaner ways, but in the interest of
      # self-hosting, I'll do this for now.
      ac = 0
      e[2].each{|a| ac += 1 if ! a.kind_of?(Array)}

      scopes = [args.dup] # We don't want "args" above to get updated 

      ri = -1
      r = e[2][ri]
      # FIXME: compiler bug; rest does not correctly get initialized to
      # nil in the control flows where it's not assigned.
      rest = nil
      if r
        if r[-1] != :rest
          ri -= 1
          r = e[2][ri]
        end
        if r && r[-1] == :rest
          rest = r[0]
        end
        if rest
          # FIXME: This is a hacky workaround
          if rest != :__copysplat
            r[0] = :__splat
          end
        end
      end

      # We use this to assign registers
      freq   = Hash.new(0)

      s = Set.new
      vars,env= find_vars(e[3],scopes,s, freq)

      env << :__closure__

      # For "preturn". see Compiler#compile_preturn
      aenv = [:__stackframe__] + env.to_a
      env << :__stackframe__

      body = e[3]
      prologue = nil
      vars -= args.to_a
      seen = false
      if env.size > 0
        seen = rewrite_env_vars(body, aenv)

        notargs = env - args - [:__closure__]

        # FIXME: Due to compiler bug
        ex = e
        extra_assigns = (env - notargs).to_a.collect do |a|
          ai = aenv.index(a)
          # FIXME: "ex" instead of "e" due to compiler bug.
          E[ex.position, :assign, E[ex.position,:index, :__env__, ai], a]
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

      if rest && rest != :__copysplat
        # rest might be a symbol or an indexed env access [:index, :__env__, N]
        # after variable renaming. Extract the symbol if needed.
        rest_sym = rest.is_a?(Symbol) ? rest : rest
        rest_target = rest  # Use original rest as assignment target

        vars << rest_sym if rest_sym.is_a?(Symbol)
        # FIXME: @bug Removing the E[] below causes segmentation fault
        rest_func =
          [E[:sexp,
           # Corrected to take into account statically provided arguments.
           [:assign, rest_target, [:__splat_to_Array, :__splat, [:sub, :numargs, ac]]]
          ]]
      else
        rest_func = nil
      end

      e[3] = []
      if rest_func
        e[3].concat(rest_func)
      end

      if seen && prologue # seen && prologue
        e[3].concat(prologue)
      end

      e[3].concat(body)

      # FIXME: Compiler bug: Changing the below to "if !vars.empty?" causes seg fault.
      empty = vars.empty?
      if empty == false
        e[3] = E[e.position,:let, vars, *e[3]]
        # We store the variables by descending frequency for future use in register
        # allocation.
        # FIXME: Compiler bug: -v fails.
        e[3].extra[:varfreq] = freq.sort_by {|k,v| 0 - v }.collect{|a| a.first }
      else
        e[3] = E[e.position, :do, *e[3]]
      end

      # Recursively process the rewritten body to handle nested defms (e.g., eigenclass methods)
      rewrite_let_env(e[3])

      :skip
    end

    # Handle top-level procs (those not inside any :defm)
    # These need environment setup and lambda rewriting too
    # This fixes blocks like: [1].each { |x| puts x } at top level
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
          inner = exp[1..-1].dup
          exp.clear
          exp << :do
          let_body = E[:do,
            E[:sexp, E[:assign, :__closure__, 0]],
            E[:sexp, E[:assign, :__env__, E[:call, :__alloc_env, 2]]]]
          inner.each { |e| let_body << e }
          exp << E[:let, [:__closure__, :__tmp_proc, :__env__], let_body]
        end
      end
    end
  end

  def rewrite_range(exp)
    exp.depth_first do |e|
      if e[0] == :range
        e.replace(E[:callm, :Range, :new, e[1..-1]])
      elsif e[0] == :exclusive_range
        # For exclusive range (...), pass true as third argument
        e.replace(E[:callm, :Range, :new, e[1], e[2], true])
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
          # Only add vtable entries if we're in a class/module scope
          # At global scope, attr_accessor applies to Object
          target_scope = scope.is_a?(ModuleScope) ? scope : scope.class_scope
          arr.each {|entry|
            target_scope.add_vtable_entry(entry.to_s[1..-1].to_sym)
            target_scope.add_ivar("@#{entry.to_s[1..-1]}".to_sym)
          }

          # Then let's do the quick hack:
          #

          type = e[1]
          syms = e[2]

          e.replace(E[:do])
          syms.each do |mname|
            mname = mname.to_s[1..-1].to_sym
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
            # Flatten Foo::Bar to Foo__Bar
            module_name = "#{module_name[1]}__#{module_name[2]}".to_sym
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
        if r.is_a?(Array) && r[0] == :array
          # Already an array literal, just assign it
          e[1] = var
        elsif r.is_a?(Array)
          # Array of values, wrap in :array
          e[1] = var
          e[2] = [:array, *r]
        else
          # Single value, wrap in array
          e[1] = var
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

        # FIXME: Are there instances where aliasing __destruct may
        # be a problem?
        e[0] = :let
        e[1] = [:__destruct]
        # Convert right-hand side to array using Array() for proper destructuring
        # Array() tries to_ary, then to_a, then wraps in array if neither exists
        # This handles cases like `x, y = 42` where 42 doesn't respond to to_a
        e[2] = [:do, [:assign, :__destruct, [:call, :Array, [r]]]]
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
            ex[2] << [:assign, v, [:callm,:__destruct,:[],[i]]]
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
              ex[2] << [:assign, v, [:callm,:__destruct,:[],[neg_idx]]]
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
            ex[2] << [:assign, splat_var,
              [:callm, :__destruct, :[],
                [[:range, [:sexp, start_idx], [:sexp, end_idx]]]]]
          else
            # No elements after splat, use range to end: __destruct[start_idx..-1]
            ex[2] << [:assign, splat_var,
              [:callm, :__destruct, :[],
                [[:range, [:sexp, start_idx], [:sexp, -1]]]]]
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
            ex[2] << [:assign, v, [:callm,:__destruct,:[],[i]]]
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

  def preprocess exp
    # The global scope is needed for some rewrites
    setup_global_scope(exp)

    rewrite_for(exp)
    rewrite_destruct(exp)

    # Pre-register constants after for/destruct rewrites create assignments
    register_constants(exp, @global_scope)

    convert_ternalt_in_calls(exp)  # Convert :ternalt to :pair for method call keyword arguments
    group_keyword_arguments(exp)   # Group :pair and :hash_splat nodes into :hash
    rewrite_concat(exp)
    rewrite_range(exp)
    rewrite_defined(exp)  # Must run before rewrite_strconst
    rewrite_strconst(exp)
    rewrite_integer_constant(exp)
    rewrite_symbol_constant(exp)
    rewrite_operators(exp)
    rewrite_yield(exp)
    rewrite_forward_args(exp)    # Must run before rewrite_keyword_args
    rewrite_keyword_args(exp)   # Must run before rewrite_default_args
    rewrite_default_args(exp)
    rewrite_let_env(exp)
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
          # Replace with: *__fwd_args__, **__fwd_kwargs__, &__fwd_block__
          new_args << [:__fwd_args__, :rest]
          new_args << [:__fwd_kwargs__, :keyrest]
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
              # Return array of arguments to be flattened in
              [[:splat, :__fwd_args__], [:hash, [:hash_splat, :__fwd_kwargs__]]]
            else
              arg
            end
          end.flatten(1)  # Flatten one level to merge the arrays

          node[args_index] = new_call_args

          # For :call nodes, block is separate; for :callm it's also separate
          # We need to set the block parameter if there's a block
          # But actually, blocks are passed differently - they're not in the args array
          # TODO: Handle block forwarding properly
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
    exp.depth_first(:defm) do |e|
      args = e[2]
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

      # Replace args with regular args + __kwargs
      new_args = regular_args + [:__kwargs]

      # Prepend keyword argument extractions to body
      body = e[3]
      body = [] unless body.is_a?(Array)
      new_body = kwarg_extractions + body

      # Update method definition
      e[2] = new_args
      e[3] = new_body
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
