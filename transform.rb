
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
        # Skip symbols in :deref nodes - they're constant/module names, not variables
        # [:deref, parent, const_name] - don't rewrite parent or const_name
        # Exception: if parent is an array (nested expression), it will be processed separately
        next if (i == 1 || i == 2) && e[0] == :deref && ex.is_a?(Symbol)
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
    # First, convert [:comma, ...] on LHS to [:destruct, ...]
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
            # If v is an array but not a known AST operator node, it's nested destructuring
            if v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :splat, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
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
              # If v is an array but not a known AST operator node, it's nested destructuring
              if v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :splat, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
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
            # Use Array#[start, length] form: [start_idx..-after_splat-1]
            # Rewrite as: __destruct[start_idx, [0, __destruct.length - start_idx - after_splat].max]
            # This handles edge cases where array is too short
            ex[2] << [:assign, splat_var,
              [:callm, :__destruct, :[],
                [start_idx,
                 [:callm,
                   [:callm, 0, :max,
                     [[:callm,
                       [:callm,
                         [:callm, :__destruct, :length],
                         :-, [start_idx]],
                       :-, [after_splat]]]],
                   :to_i]]]]
          else
            # No elements after splat, use range to end: __destruct[start_idx..-1]
            ex[2] << [:assign, splat_var,
              [:callm, :__destruct, :[],
                [[:range, start_idx, -1]]]]
          end
        else
          # No splat: simple destructuring
          vars.each_with_index do |v,i|
            # If v is an array but not a known AST operator node, it's nested destructuring
            # Wrap it in :destruct so it gets expanded recursively
            if v.is_a?(Array) && ![:deref, :callm, :index, :call, :sexp, :pair, :ternalt, :hash, :array, :splat, :rest, :block, :keyrest, :key, :keyreq].include?(v[0])
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

  def preprocess exp
    # The global scope is needed for some rewrites
    setup_global_scope(exp)

    rewrite_for(exp)
    rewrite_destruct(exp)
    rewrite_concat(exp)
    rewrite_range(exp)
    rewrite_strconst(exp)
    rewrite_integer_constant(exp)
    rewrite_symbol_constant(exp)
    rewrite_operators(exp)
    rewrite_yield(exp)
    rewrite_default_args(exp)
    rewrite_let_env(exp)
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
