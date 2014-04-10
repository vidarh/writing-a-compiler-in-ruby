# 
# Parts of the compiler class that mainly transform the source tree
#
# Ideally these will be broken out of the Compiler class at some point
# For now they're moved here to start refactoring.
#

class Compiler
  include AST

  # This replaces the old lambda handling with a rewrite.
  # The advantage of handling it as a rewrite phase is that it's
  # much easier to debug - it can be turned on and off to 
  # see how the code gets transformed.
  def rewrite_lambda(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      if e[0] == :lambda
        args = e[1] || E[]
        body = e[2] || nil
        e.clear
        e[0] = :do
        e[1] = E[:assign, :__tmp_proc, 
          E[:defun, @e.get_local,
            E[:self,:__closure__,:__env__]+args,
            body]
        ]
        e[2] = E[exp.position,:sexp, E[:call, :__new_proc, E[:__tmp_proc, :__env__]]]
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


  # Rewrite a numeric constant outside %s() to
  # %s(call __get_fixnum val)
  def rewrite_fixnumconst(exp)
    exp.depth_first do |e|
      next :skip if e[0] == :sexp
      is_call = e[0] == :call || e[0] == :callm
      e.each_with_index do |v,i|
        if v.is_a?(Integer)
          e[i] = E[:sexp, E[:call, :__get_fixnum, v]]

          # FIXME: This is a horrible workaround to deal with a parser
          # inconsistency that leaves calls with a single argument with
          # the argument "bare" if it's not an array, which breaks with
          # this rewrite.
          e[i] = E[e[i]] if is_call && i > 1
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
        e[3] = E[e[2]]
        e[2] = e[0]
        e[0] = :callm
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
    Compiler::Keywords.member?(v) || v == :nil || v == :self ||
      v.to_s[0] == ?@ ||
      v == :true || v == :false  || v.to_s[0] < ?a
  end

  def push_var(scopes, env, v)
    sc = in_scopes(scopes,v)
    if sc.size == 0 && !env.member?(v) && !is_special_name?(v)
      scopes[-1] << v 
    end
  end

  # FIXME: Rewrite using "depth first"?
  def find_vars(e, scopes, env, freq, in_lambda = false, in_assign = false)
    return [],env, false if !e
    e = [e] if !e.is_a?(Array)
    e.each do |n|
      if n.is_a?(Array)
        if n[0] == :assign
          vars1, env1 = find_vars(n[1],     scopes + [Set.new],env, freq, in_lambda, true)
          vars2, env2 = find_vars(n[2..-1], scopes + [Set.new],env, freq, in_lambda)
          env = env1 + env2
          vars = vars1+vars2
          vars.each {|v| push_var(scopes,env,v) }
        elsif n[0] == :lambda
          vars, env = find_vars(n[2], scopes + [Set.new],env, freq, true)
          n[2] = E[n.position,:let, vars, *n[2]] if n[2]
        else
          if    n[0] == :callm 
            vars, env = find_vars(n[1], scopes, env, freq, in_lambda)
            if n[3]
              nodes = n[3]
              nodes = [nodes] if !nodes.is_a?(Array)
              nodes.each do |n2|
                vars2, env2 = find_vars(n2, scopes, env, freq, in_lambda)
                vars += vars2
                env  += env2
              end
            end
          else
            if n[0] == :call
              sub = n[2..-1]
            else 
              sub = n[1..-1]
            end
            vars, env = find_vars(sub, scopes, env, freq, in_lambda)
          end

          vars.each {|v| push_var(scopes,env,v); }
        end
      elsif n.is_a?(Symbol)
        sc = in_scopes(scopes,n)
        freq[n] += 1 if !is_special_name?(n)
        if sc.size == 0
          push_var(scopes,env,n) if in_assign
        elsif in_lambda
          sc.first.delete(n)
          env << n
        end
      end
    end
    return scopes[-1].to_a, env
  end


  def rewrite_env_vars(exp, env)
    exp.depth_first do |e|
      STDERR.puts e.inspect
      e.each_with_index do |ex, i|
        num = env.index(ex)
        if num
          e[i] = E[:index, :__env__, num]
        end
      end
    end
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
      scopes = [args.dup] # We don't want "args" above to get updated 

      # We use this to assign registers
      freq   = Hash.new(0)

      vars,env= find_vars(e[3],scopes,Set.new, freq)

      vars -= args.to_a
      if env.size > 0
        body = e[3]

        rewrite_env_vars(body, env.to_a)
        notargs = env - Set[*e[2]]
        aenv = env.to_a
        extra_assigns = (env - notargs).to_a.collect do |a|
          E[e.position,:assign, E[e.position,:index, :__env__, aenv.index(a)], a]
        end
        e[3] = [E[:sexp,E[:assign, :__env__, E[:call, :malloc,  [env.size * 4]]]]]
        e[3].concat(extra_assigns)
        e[3].concat(body)
      end
      # Always adding __env__ here is a waste, but it saves us (for now)
      # to have to intelligently decide whether or not to reference __env__
      # in the rewrite_lambda method
      vars << :__env__
      vars << :__tmp_proc # Used in rewrite_lambda. Same caveats as for __env_

      e[3] = E[e.position,:let, vars,*e[3]]

      # We store the variables by descending frequency for future use in register
      # allocation.
      e[3].extra[:varfreq] = freq.sort_by {|k,v| -v }.collect{|a| a.first }

      :skip
    end
  end

  def create_concat(sub)
    right = sub.pop
    right = E[:callm,right,:to_s] if !right.is_a?(Array)
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

  def preprocess exp
    rewrite_concat(exp)
    rewrite_strconst(exp)
    rewrite_fixnumconst(exp)
    rewrite_operators(exp)
    rewrite_let_env(exp)
    rewrite_lambda(exp)
  end
end
