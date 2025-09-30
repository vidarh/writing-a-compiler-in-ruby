
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
        args = e[1] || E[]
        body = e[2] || nil

        if e[0] == :proc && body
          body = rewrite_proc_return(body)
        end

        # FIXME: Putting this inline further down appears to break.
        len = args.length

        e.replace(
          E[:do,
            [:assign, [:index, :__env__,0], [:stackframe]],
            [:assign, :__tmp_proc,
              [:defun, "__lambda_#{@e.get_local[1..-1]}",
                [:self,:__closure__,:__env__]+args.collect{|a| [a, :default, :nil] },
                body
              ]
            ],
            # FIXME: Compiler bug: This works
            [:sexp, [:call, :__new_proc, [:__tmp_proc, :__env__, :self, len]]]
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
      # FIXME: This is a workaround for a compiler @bug
      bug=e
      e.each_with_index do |s,i|
        if s.is_a?(String)
          lab = @string_constants[s]
          if !lab
            lab = @e.get_local
            @string_constants[s] = lab
          end
          # FIXME: This is a workaround for a compiler bug
          # STDERR.puts(bug.inspect)
          bug[i] = E[:sexp, E[:call, :__get_string, lab.to_sym]]

          # FIXME: This is a horrible workaround to deal with a parser
          # inconsistency that leaves calls with a single argument with
          # the argument "bare" if it's not an array, which breaks with
          # this rewrite.
          bug[i] = E[bug[i]] if is_call && i > 1
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

  def find_vars_ary(ary, scopes, env, freq, in_lambda = false, in_assign = false)
    vars = []
    ary.each do |e|
      vars2, env2 = find_vars(e, scopes, env, freq, in_lambda, in_assign)
      vars += vars2
      env  += env2
    end
    return vars
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
          vars.each {|v| push_var(scopes,env,v) if !is_special_name?(v) }
        elsif n[0] == :lambda || n[0] == :proc
          vars, env2= find_vars(n[2], scopes + [Set.new],env, freq, true)

          # Clean out proc/lambda arguments from the %s(let ..) and the environment we're building
          vars  -= n[1] if n[1]
          env2  -= n[1] if n[1]
          env += env2

          n[2] = E[n.position,:let, vars, *n[2]] if n[2]
        else
          if    n[0] == :callm
            vars, env = find_vars(n[1], scopes, env, freq, in_lambda)

            if n[3]
              nodes = n[3]
              nodes = [nodes] if !nodes.is_a?(Array)
              nodes.each do |n2|
                vars2, env2 = find_vars([n2], scopes+[Set.new], env, freq, in_lambda)
                vars += vars2
                env  += env2
              end
            end

            # If a block is provided, we need to find variables there too
            if n[4]
              vars3, env3 = find_vars([n[4]], scopes, env, freq, in_lambda)
              vars += vars3
              env  += env3
            end
          elsif    n[0] == :call
            vars, env = find_vars(n[1], scopes, env, freq, in_lambda)
            if n[2]
              nodes = n[2]
              nodes = [nodes] if !nodes.is_a?(Array)
              nodes.each do |n2|
                vars2, env2 = find_vars(n2, scopes+[Set.new], env, freq, in_lambda)
                vars += vars2
                env  += env2
              end
            end

            if n[3]
              vars2, env2 = find_vars([n[3]], scopes, env, freq, in_lambda)
              vars += vars2
              env  += env2
            end
          else
            vars, env = find_vars(n[1..-1], scopes, env, freq, in_lambda)
          end

          vars.each {|v| push_var(scopes,env,v); }
        end
      elsif n.is_a?(Symbol)
        sc = in_scopes(scopes[0..-2],n)
        freq[n] += 1 if !is_special_name?(n)
        if sc.size == 0
          push_var(scopes,env,n) if in_assign && !is_special_name?(n)
        elsif in_lambda
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
      # We need to expand "yield" before we rewrite.
      if e.is_a?(Array) && e[0] == :call && e[1] == :yield
        seen = true
        args = e[2]
        e[0] = :callm
        e[1] = :__closure__
        e[2] = :call
        e[3] = args
      end

      # FIXME: @bug; see below.
      eary = e
      e.each_with_index do |ex, i|
        # FIXME: This is necessary in order to avoid rewriting compiler keywords in some
        # circumstances. The proper solution would be to introduce more types of 
        # expression nodes in the parser
        next if i == 0 && ex == :index
        num = env.index(ex)
        if num
          seen = true
          # FIXME: @bug; e[i] causes segfault.
          eary[i] = E[:index, :__env__, num]
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

      vars,env= find_vars(e[3],scopes,Set.new, freq)

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
        vars << rest.to_sym
        # FIXME: @bug Removing the E[] below causes segmentation fault
        rest_func =
          [E[:sexp,
           # Corrected to take into account statically provided arguments.
           [:assign, rest.to_sym, [:__splat_to_Array, :__splat, [:sub, :numargs, ac]]]
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

      :skip
    end
  end

  def rewrite_range(exp)
    exp.depth_first do |e|
      if e[0] == :range
        e.replace(E[:callm, :Range, :new, e[1..-1]])
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
          arr.each {|entry|
            scope.add_vtable_entry(entry.to_s[1..-1].to_sym)
            scope.add_ivar("@#{entry.to_s[1..-1]}".to_sym)
          }

          # Then let's do the quick hack:
          #

          type = e[1]
          syms = e[2]

          e.replace(E[:do])
          # FIXME: Workaround for compiler @bug
          ex = e
          syms.each do |mname|
            mname = mname.to_s[1..-1].to_sym
            if (type == :attr_reader || type == :attr_accessor)
              ex << E[:defm, mname, [], ["@#{mname}".to_sym]]
            end
            if (type == :attr_writer || type == :attr_accessor)
              ex << E[:defm, "#{mname}=".to_sym, [:value], [[:assign, "@#{mname}".to_sym, :value]]]
            end
          end
        elsif e[0] == :class
          # FIXME: While splitting this out is a reasonable
          # refactoring step; it was done as a workaround for a compiler @bug
          build_class_scopes_for_class(e, scope)
        elsif e[0] == :module
          cscope   = @classes[e[1].to_sym]
          cscope ||= ModuleScope.new(scope, e[1], @vtableoffsets, @classes[:Object])
          @classes[cscope.name.to_sym] =  cscope
          @global_scope.add_constant(cscope.name.to_sym,cscope)
          scope.add_constant(e[1].to_sym,cscope)
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
    superc = @classes[superclass.to_sym]
    name = e[1]
    if name.is_a?(Array) && name[0] == :eigen
      name = clean_method_name(name.to_s)
    end
    cscope = @classes[name.to_sym]
    cscope = ClassScope.new(scope, name, @vtableoffsets, superc) if !cscope
    @classes[cscope.name.to_sym] =  cscope
    @global_scope.add_constant(cscope.name.to_sym,cscope)
    scope.add_constant(name.to_sym,cscope)
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
  def rewrite_destruct(exps)
    exps.depth_first(:assign) do |e|
      l = e[1]
      if l.is_a?(Array) && l[0] == :destruct
        vars = l[1..-1]
        r = e[2]

        # FIXME: Are there instances where aliasing __destruct may
        # be a problem?
        e[0] = :let
        e[1] = [:__destruct]
        e[2] = [:do, [:assign, :__destruct, r]]
        ex = e
        vars.each_with_index do |v,i|
          ex[2] << [:assign, v, [:callm,:__destruct,:[],[i]]]
        end
      end
    end
  end

  def rewrite_yield(exps)
    exps.depth_first(:yield) do |e|
      e[0] = [:call, :yield]
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

    rewrite_destruct(exp)
    rewrite_concat(exp)
    rewrite_range(exp)
    rewrite_strconst(exp)
    rewrite_integer_constant(exp)
    rewrite_symbol_constant(exp)
    rewrite_operators(exp)
    rewrite_yield(exp)
    rewrite_let_env(exp)
  end
end
