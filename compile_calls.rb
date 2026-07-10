#
# Method related to function and method calls,
# including yield and super.
#
#

class Compiler

  def compile_args_nosplat(scope, ob, args, dynamic_adj = false, &block)
    # FIXME: This used to use "with_stack" which aligns to 16 byte boundaries,
    # but lifted this in here due to dynamically adjusting the stack based on
    # %ebx. Need to determine exactly what to do about this size - it needs to
    # be bigger than args.length for some reason, but unsure exactly why and
    # how much.
    len = args.length
    adj = Emitter::PTR_SIZE * (len+4)
    @e.subl(adj, :esp)
    # Index while-loop instead of each_with_index: this compiles the args of EVERY call, and
    # each_with_index's block/enumerator dispatch is a hot allocator on both hosts.
    i = 0
    while i < len
      param = compile_eval_arg(scope, args[i])
      @e.save_to_stack(param, i)
      i += 1
    end
    @e.movl(len, :ebx)

    yield

    if dynamic_adj
      # Always dynamically adjust the stack based on %ebx for method calls
      # (as opposed to C-library calls) due to potential of hitting a
      # method_missing thunk or anything else that might mess around with the
      # argument list before returning from the call.
      @e.comment(Emitter::COMMENTS && "Static adj: #{adj}")
      @e.addl(4, :ebx) # Need to correspond to the extra space used when assigning "adj" above.
      @e.sall(2, :ebx) 
      @e.addl(:ebx, :esp)
    else
      @e.addl(adj, :esp)
    end
  end

  def copy_splat_loop(splatcnt, indir)
    @e.loop do |br,_|
      @e.testl(splatcnt, splatcnt)
      @e.je(br)
      # x86 will be the death of me.
      @e.pushl("(%eax)")
      @e.popl("(%#{indir.to_s})")
      @e.addl(4,:eax)
      @e.addl(4,indir)
      @e.subl(1,splatcnt)
    end
  end

  # For a splat argument, push it onto the stack,
  # forwards relative to register "indir".
  #
  # Number of fixed argument slots preceding a forwarded `*__copysplat` rest param in the ENCLOSING
  # method: the raw-splat forward copies `numargs - <this>` slots out of the caller's argument area.
  # It was hardcoded to 2 (self + __closure__), which is right for `def call(*__copysplat)`-shaped
  # methods but copied ONE EXTRA slot (a stray stack word -- e.g. a Proc -- appended to the args) for
  # any method with a named param before the splat, like `__call_with_self(newself, *__copysplat)`.
  # Compute it from the method's own arg list (a &block param is popped from Function#args and takes
  # no positional slot). Falls back to 2 when no enclosing function is visible.
  def copysplat_fixed_count(scope)
    f = scope.method
    if f && f.respond_to?(:args) && f.args
      idx = nil
      i = 0
      while i < f.args.length
        a = f.args[i]
        if a.respond_to?(:rest?) && a.rest?
          idx = i
          break
        end
        i += 1
      end
      return idx if idx
    end
    2
  end

  # FIXME: This method is almost certainly much
  # less efficient than it could be.
  #
  def compile_args_copysplat(scope, a, indir)
    @e.with_register do |splatcnt|
      if a[1] == :__copysplat
        @e.comment(Emitter::COMMENTS && "SPLAT COPY")
        param = @e.save_to_reg(compile_eval_arg(scope, [:sub, :numargs, copysplat_fixed_count(scope)]))
        @e.movl(param, splatcnt)
        param = compile_eval_arg(scope, a[1])
        copy_splat_loop(splatcnt, indir)
      else
        @e.comment(Emitter::COMMENTS && "SPLAT ARRAY")
        param = compile_eval_arg(scope, a[1])
        @e.addl(4,param)
        @e.load_indirect(param, splatcnt)
        @e.addl(4,param)
        @e.load_indirect(param, :eax)
        @e.testl(:eax,:eax)
        l = @e.get_local

        # If Array class ptr has not been allocated yet:
        @e.je(l)
        copy_splat_loop(splatcnt, indir)
        @e.local(l)
      end
    end

  end

  def compile_args_splat_loop(scope, args, indir)
    args.each do |a|
      ary = a.is_a?(Array)
      sp = false
      if ary
        if a[0] == :splat
          sp = true
        end
      end
      # ary && (a[0] == :splat)
      if sp
        compile_args_copysplat(scope, a, indir)
      else
        param = compile_eval_arg(scope, a)
        @e.save_indirect(param, indir)
        @e.addl(4, indir)
      end
    end
  end

  def compile_args_splat(scope, ob, args)
    # Because Ruby evaluation order is left to right,
    # we need to first figure out how much space we need on
    # the stack.
    #
    # We do that by first building up an expression that
    # adds up the static elements of the parameter list
    # and the result of retrieving 'Array#length' from
    # each splatted array.
    #
    # (FIXME: Note that we're not actually type-checking
    # what is *actually* passed)
    #
    num_fixed = 0
    exprlist = []
    args.each_with_index do |a, i|
      if a.is_a?(Array) && a[0] == :splat
        if a[1] == :__copysplat
          exprlist << [:sub, :numargs, copysplat_fixed_count(scope)]
        else
          # We do this, rather than Array#length, because the class may not
          # have been created yet. This *requires* Array's @len ivar to be
          # in the first ivar;
          # FIXME: should enforce this.
          exprlist << [:index, a[1], 1]
        end
      else
        num_fixed += 1
      end
    end
    expr = num_fixed
    while e = exprlist.pop
      expr = [:add, e, expr]
    end

    @e.comment(Emitter::COMMENTS && "BEGIN Calculating argument count for splat")
    ret = compile_eval_arg(scope, expr)
    @e.movl(@e.result, @e.scratch)
    @e.comment(Emitter::COMMENTS && "END Calculating argument count for splat; numargs is now in #{@e.scratch.to_s}")

    @e.comment(Emitter::COMMENTS && "Moving stack pointer to start of argument array:")
    @e.imull(4,@e.result)

    # esp now points to the start of the arguments; ebx holds numargs,
    # and end_of_arguments(%esp) also holds numargs
    @e.subl(@e.result, :esp)

    @e.comment(Emitter::COMMENTS && "BEGIN Pushing arguments:")
    @e.with_register do |indir|
      # We'll use indir to put arguments onto the stack without clobbering esp:
      @e.movl(:esp, indir)
      @e.pushl(@e.scratch)
      @e.comment(Emitter::COMMENTS && "BEGIN args.each do |a|")
      compile_args_splat_loop(scope, args, indir)
      @e.comment(Emitter::COMMENTS && "END args.each")
      @e.popl(@e.scratch)
    end
    @e.comment(Emitter::COMMENTS && "END Pushing arguments")
    yield
    @e.comment(Emitter::COMMENTS && "Re-adjusting stack post-call:")
    @e.imull(4,@e.scratch)
    @e.addl(@e.scratch, :esp)
  end

  def compile_args(scope, ob, args, dynamic_adjust=false, &block)
    @e.caller_save do
      splat = args.detect {|a| a.is_a?(Array) && a.first == :splat }

      #FIXME Mentioned here to lift vars
      scope
      block
      dynamic_adjust

      if !splat
        compile_args_nosplat(scope,ob,args,dynamic_adjust, &block)
      else
        compile_args_splat(scope,ob,args, &block)
      end
    end
  end

  def compile_callm_args(scope, ob, args, &block)
    compile_args(scope, ob, [ob].concat(args), true, &block)
  end



  # Compiles a function call.
  # Takes the current scope, the function to call as well as the arguments
  # to call the function with.
  def compile_call(scope, func, args, block = nil, pos = nil)
    return compile_yield(scope, args, block) if func == :yield

    # Handle visibility methods, attr, and module_function at compile time
    # These are no-ops since visibility isn't enforced and attr_* are stubs
    # But we need to handle them here because method calls in class bodies
    # don't work correctly (self/%esi not set up properly)
    # module_function makes methods both module methods and private instance methods
    # undef_method is a no-op here, matching the `undef` keyword (compile_undef). Without it, class
    # bodies that call undef_method (common in rubyspec fixtures) crash with "undefined method
    # 'undef_method'" while the fixture loads, taking out every spec that requires that fixture.
    if [:private, :protected, :public, :attr, :attr_reader, :attr_writer, :attr_accessor, :module_function, :undef_method, :private_constant, :public_constant, :private_class_method, :public_class_method, :autoload].include?(func)
      # Normally these are no-ops in a class/module body (ModuleScope). When the body wraps its statements
      # in a LocalVarScope (compile_class does this to provide __env__ for class-level closures), the scope
      # is a LocalVarScope whose immediate parent is that ModuleScope -- still a class-body context, so the
      # no-op must apply there too (otherwise `protected`/`attr_*`/... fall through to a bogus self.<name>
      # call -> "undefined method 'protected'").
      if scope.is_a?(ModuleScope) ||
         (scope.is_a?(LocalVarScope) && scope.respond_to?(:next) && scope.next.is_a?(ModuleScope))
        # In class/module body - just return nil
        @e.movl("nil", :eax)
        return Value.new([:subexpr])
      end
      # Fall through to regular method call in other contexts
    end

    # Handle 'include' and 'prepend' as compile-time module inclusion
    # Works in:
    # - ClassScope/ModuleScope (class/module body) - includes into that class/module
    # - GlobalScope (top level) - includes into Object
    # Other scopes (LocalVarScope, etc.) - treat as regular method call
    # Note: prepend is treated same as include (ordering difference not implemented)
    if func == :include || func == :prepend
      if scope.is_a?(ModuleScope) || scope.is_a?(GlobalScope)
        # args is array of module names, but we only support single module for now
        mod_name = args.is_a?(Array) ? args[0] : args

        # Handle compile-time constant names. A plain Symbol goes to compile_include. A simple nested
        # constant (include Foo::Bar -> [:deref, :Foo, :Bar]) is routed only when it actually resolves
        # statically -- compile_include raises "Module not found" otherwise, and a deeper form like
        # Foo::Bar::Baz ([:deref, [:deref, ...], :Baz]) it can't resolve at all. Anything unresolvable
        # (or dynamic) falls through to a runtime method call, as before.
        if mod_name.is_a?(Symbol)
          return compile_include(scope, mod_name, pos)
        elsif mod_name.is_a?(Array) && mod_name[0] == :deref && mod_name.length == 3 && mod_name[1].is_a?(Symbol)
          parent = scope.find_constant(mod_name[1])
          if parent && parent.is_a?(ModuleScope) && parent.find_constant(mod_name[2])
            return compile_include(scope, mod_name, pos)
          end
        end
        # Fall through to regular method call for dynamic/unresolvable module names
      else
        # Not in class/module/global scope - fall through to regular method call
        # This allows include to work as a method in other contexts (e.g., RSpec matchers)
      end
    end

    # Handle 'extend' at compile time - no-op for now
    # (proper implementation would add module methods to singleton class)
    if func == :extend
      if scope.is_a?(ModuleScope)
        @e.movl("nil", :eax)
        return Value.new([:subexpr])
      end
    end

    # This is a bit of a hack. get_arg will also be called from
    # compile_eval_arg below, but we need to know if it's a callm
    fargs = get_arg(scope, func)

    return compile_super(scope, args,block) if func == :super
    return compile_callm(scope,:self, func, args,block) if fargs and fargs[0] == :possible_callm || fargs[0] == :global

    # `name(...)` with explicit call syntax is ALWAYS a method call in Ruby, even when a parameter (or
    # rest parameter) of the same name is in scope -- a bare local/param can only be invoked via
    # `name.call` / `name.()` / `name[]`. Without this, `-> a=a() { a }` compiled the default value's
    # `a()` as an indirect call THROUGH the (still unset) parameter slot and jumped to a tagged-integer
    # "address", segfaulting. Route such calls to normal method dispatch on self instead. (Only :arg/
    # :argaddr -- parameters -- are redirected; :lvar/ivar/global resolutions are left as-is.)
    return compile_callm(scope,:self, func, args,block) if func.is_a?(Symbol) && fargs && (fargs[0] == :arg || fargs[0] == :argaddr)

    # The same applies to a LOCAL of the same name: a DEFAULTED parameter lives in a local slot
    # (:lvar), so in `def foo(bar = bar()); bar; end` the default expression's explicit `bar()`
    # compiled as an indirect `call *%slot` through the just-nil'd local -> jump to the nil object ->
    # SIGSEGV. Ruby-level `name()` never calls through a variable, so dispatch on self. Raw
    # s-expressions DO use `(call var ...)` for genuine indirect calls through function-pointer
    # variables, so anything under a SexpScope (every %s(...) body) keeps the low-level behaviour.
    if func.is_a?(Symbol) && fargs && fargs[0] == :lvar && !scope_has_sexpscope?(scope)
      return compile_callm(scope,:self, func, args,block)
    end

    # Wrap single argument in array if needed
    # When there's a block, parser passes args unwrapped: [:call, func, arg, block]
    # When there's no block, parser wraps args: [:call, func, [args...]]
    # Only wrap if it's an AST node (not a symbol/constant name)
    if !args.is_a?(Array)
      args = [args]
    elsif block && args.is_a?(Array) && args[0].is_a?(Symbol) &&
          (@@keywords.include?(args[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(args[0]))
      # With a block, a SINGLE AST-node argument arrives unwrapped, e.g. `foo(-> {}) do..end` (the lambda
      # is rewritten to a [:do,...] node by this point) or `foo(recv.m) do..end` ([:callm,...]). args[0]
      # is then the node's tag, and treating args as an arg LIST would iterate the tag as a bogus method
      # (`undefined method 'do'/'callm'`). Recognise any node tag -- @@keywords covers :do/:hash/:array/
      # :if/... and the call forms are added explicitly (they are excluded from @@keywords). A genuine
      # multi-arg list has a value/[:node]-array/non-keyword-symbol first element, so it is not wrapped.
      args = [args]
    end
    compile_args(scope, func, args) do
      scope
      func

      r = get_arg(scope,func)
      if r[0] == :addr
        @e.call(r[1].to_s)
      else
        @e.call(compile_eval_arg(scope, func))
      end
    end

    @e.evict_regs_for(:self)
    reload_self(scope)
    return Value.new([:subexpr])
  end


  # Load class for the object whose pointer is in %esi.
  #
  # For now, this is done by testing bit 0, and if it
  # is set we know this isn't a valid pointer to a Class
  # object. Instead we assume it is a Fixnum.
  #
  # This is similar to MRI, but MRI uses type tags for
  # more types of objects. We probably will here too
  # in the future (e.g. Float when it's added, at least)
  #
  # Upside: Far less need for garbage collection.
  # Downside: The cost of *this* every time we need the
  # class pointer. This can be mitigated somewhat by
  # better code generation (e.g. keeping class pointers
  # for objects that are accessed multiple times;
  # figuring out inlining and the like, but requires more
  # effort to optimize. As a first stage, however, this
  # will do as it makes self-compilation viable for this
  # compiler for the first time.
  #
  def load_class(scope)
    @e.testl(1, :esi)
    l1 = @e.get_local
    l2 = @e.get_local
    @e.jz(l1)
    @e.load(:global, :Fixnum)
    @e.jmp(l2)
    @e.label(l1)
    @e.load_indirect(:esi, :eax)
    @e.label(l2)
  end

  # Load the super-class pointer
  def load_super(scope)
    @e.load_instance_var(:eax, 3)
    # Slot 3 (superclass) is 0 for the bootstrap roots (e.g. Object), so `super`
    # from a method defined there -- a toplevel def, or a block's zsuper resolving
    # to one -- used to emit `call *voff(0)`: a NULL call -> SIGSEGV. Substitute
    # __base_vtable, the table of method_missing thunks used to fill unimplemented
    # vtable slots: the dispatch then raises NoMethodError through the normal
    # missing-method path instead of crashing.
    l_ok = @e.get_local
    @e.testl(:eax, :eax)
    @e.jne(l_ok)
    @e.movl(@e.addr_value("__base_vtable"), :eax)
    @e.label(l_ok)
  end

  # if we called a method on something other than self,
  # or a function, we have or may have clobbered %esi,
  # so lets reload it.
  def reload_self(scope)
    t,a = get_arg(scope,:self)
    if t == :global && a != :self
      # In a class/module body self is the class object, addressable via its global.
      # get_arg alone emits no reload, so a clobbered %esi (any low-level call, e.g.
      # __get_string while building arguments) made self-dispatch go through a stale
      # table: `self.config(...)` in a subclass body raised "undefined method".
      @e.load(:global, a, :esi)
    end
  end

  # FIXME: @bug May need to do this as a rewrite, as if block is taken in, and
  # then another block is passed to another method, that other method can not
  # contain "yield", as it needs to go through a let_env rewrite.
  #
  # Yield to the supplied block
  def compile_yield(scope, args, block)
    @e.comment(Emitter::COMMENTS && "yield")
    args ||= []
    compile_callm(scope, :__closure__, :call, args, block)
  end

  # Compiles a super method call
  #
  def compile_super(scope, args, block = nil)
    # Walk up the scope chain to find an actual method (not a block/lambda)
    # Blocks have string names like "__lambda_L229", methods have symbol names like :here
    method = nil
    s = scope
    while s
      if s.method && s.method.name.is_a?(Symbol)
        method = s.method.name
        break
      end
      s = s.is_a?(Scope) ? s.next : nil
    end
    method ||= :__unknown__

    @e.comment(Emitter::COMMENTS && "super #{method.inspect}")
    trace(nil, @trace && "=> super #{method.inspect}\n")
    # Pass the defining class name so we look up the right superclass
    # (not self.class.superclass which would be wrong for deep hierarchies)
    # For eigenclasses, fall back to runtime lookup since they don't have globals
    cs = scope.class_scope
    # A method defined inside a block (Class.new(Base) do def m; super; end end) is installed on a class
    # only known at runtime; its lexical class_scope is the enclosing Object, NOT the class it lands on, so
    # loading that class by name and taking its superclass gives the wrong (or a crashing) result. Resolve
    # such supers -- and eigenclass supers, which likewise have no global -- via self.class.superclass at
    # runtime. Find the enclosing method's Function to check the block_def flag.
    mfunc = nil
    s2 = scope
    while s2
      if s2.respond_to?(:method) && s2.method && s2.method.name.is_a?(Symbol)
        mfunc = s2.method
        break
      end
      s2 = s2.is_a?(Scope) ? s2.next : nil
    end
    block_def = mfunc.respond_to?(:block_def) && mfunc.block_def
    if cs.is_a?(EigenclassScope) || block_def
      defining_class = :runtime
    else
      defining_class = cs.name
    end
    ret = compile_callm(scope, :self, method, args, block, defining_class)
    trace(nil, @trace && "<= super #{method.inspect}\n")
    ret
  end

  # Compiles a method call to an object.
  # Similar to compile_call but with an additional object parameter
  # representing the object to call the method on.
  # The object gets passed to the method, which is just another function,
  # as the first parameter.
  def compile_callm(scope, ob, method, args, block = nil, do_load_super = false)
    # FIXME: Shouldn't trigger - probably due to the callm rewrites
    return compile_yield(scope, args, block) if method == :yield and ob == :self
    return compile_super(scope, args,block) if method == :super and ob == :self

    # Special handling for defined?() - don't evaluate arguments, just stub to nil
    if method == :defined? && ob == :self
      @e.comment(Emitter::COMMENTS && "defined?() - stubbed to nil")
      return compile_exp(scope, :nil)
    end

    # Handle visibility methods, attr, and module_function at compile time in class/module bodies
    # These are no-ops since visibility isn't enforced and attr_* are stubs
    # This handles the case where the call is to self (e.g., "module_function" in module body)
    if ob == :self && scope.is_a?(ModuleScope)
      if [:private, :protected, :public, :attr, :attr_reader, :attr_writer, :attr_accessor, :module_function].include?(method)
        @e.comment(Emitter::COMMENTS && "Compile-time: #{method} in class/module body - no-op")
        @e.movl("nil", :eax)
        return Value.new([:subexpr])
      end
    end

    @e.comment(Emitter::COMMENTS && "callm #{ob.inspect}.#{method.inspect}")
    trace(nil, @trace && "=> callm #{ob.inspect}.#{method.inspect}\n")

    stackfence do
      args ||= []
      # Wrap single argument in array if needed
      # Same issue as compile_call - parser generates inconsistent structures with blocks
      # Only wrap if it's an AST node (not a symbol/constant name)
      if !args.is_a?(Array)
        args = [args]
      elsif block && args.is_a?(Array) && args.length > 1 && args[0].is_a?(Symbol) &&
            (@@keywords.include?(args[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(args[0]))
        # With a block, a SINGLE AST-node argument arrives unwrapped (e.g. `obj.m(-> {}) do..end`, where
        # the lambda is a [:do,...] node by now, or `obj.m(recv.x) do..end` -> [:callm,...]). args[0] is
        # then the node tag; treating args as an arg LIST would iterate the tag as a bogus method. Any
        # node tag qualifies (@@keywords + the call forms, which are excluded from @@keywords). A real
        # multi-arg list has a value/[:node]-array/non-keyword-symbol first element, so it is left alone.
        # The `args.length > 1` guard is essential: a genuine unwrapped node ([:do,...]/[:callm,...]) always
        # carries children, whereas a one-element arg LIST holding a single variable whose name happens to
        # be a keyword (e.g. `obj.m(pattern) do..end`, args == [:pattern]) must NOT be treated as a node --
        # doing so sent it to compile_exp, which dispatched the `:pattern` keyword to a missing method.
        args = [args]
      end

      if args.last.kind_of?(Array) && args.last[0] == :to_block
        block = args.last[1]
        # `&:sym` must pass Symbol#to_proc, not the bare symbol (Ruby's &-to_proc conversion). A symbol
        # literal has already been rewritten to [:sexp, :__S_<name>] by this point; convert only that form
        # so &proc / &block / &nil (plain vars / env reads) stay untouched and nil remains no-block.
        if block.is_a?(Array) && block[0] == :sexp && block[1].is_a?(Symbol) && block[1].to_s.start_with?("__S_")
          block = [:callm, block, :to_proc]
        end
        args.pop
      end

      args = [block ? block : 0] + args

      off = nil
      if method.is_a?(Symbol)
        off = @vtableoffsets.get_offset(method)
        if !off
          # Argh. Ok, then. Lets do send
          off = @vtableoffsets.get_offset(:__send__)
          args.insert(1,":#{method}".to_sym)
          m = off
        else
          m = "__voff__#{clean_method_name(method)}"
        end
      else
        # In this case, the method is provided as an expression
        # generating the *address*, which is evaluated beow.
      end

      compile_callm_args(scope, ob, args) do
        if ob != :self
          @e.load_indirect(@e.sp, :esi)
        else
          @e.comment(Emitter::COMMENTS && "Reload self?")
          reload_self(scope)
        end

        if do_load_super && do_load_super != :runtime
          # do_load_super is the defining class name - load its superclass directly
          # This fixes super in deep hierarchies (A < B < C) where self.class.superclass
          # would return the wrong class
          @e.comment(Emitter::COMMENTS && "Load defining class #{do_load_super} for super")
          @e.load(:global, do_load_super.to_sym)
          load_super(scope) # Load superclass from %eax
        elsif do_load_super == :runtime
          # Runtime lookup - used for eigenclasses where the class object is
          # created at runtime and has no global symbol
          load_class(scope) # Load self.class into %eax
          load_super(scope) # Load superclass from %eax
        else
          load_class(scope) # Load self.class into %eax
        end

        if off
          @e.callm(m)
        else
          # NOTE: The expression in "method" can not
          # include a function call, as it'll clobber
          # %ebx
          @e.call(compile_eval_arg(scope,method))
        end

        # FIXME: Unsure if the below check is
        # inherently unsafe, or currently unsafe
        # due to abug elsewhere, but removing it
        # solves some register invalidation problems,
        # so commenting out for now.
#        if ob != :self
          @e.comment(Emitter::COMMENTS && "Evicting self")
          @e.evict_regs_for(:self)
#        end
      end
    end

    @e.comment(Emitter::COMMENTS && "callm #{ob.to_s}.#{method.to_s} END")
    trace(nil, @trace && "<= callm #{ob.to_s}.#{method.to_s}\n")

    return Value.new([:subexpr], :object)
  end

  # Compile safe navigation operator: obj&.method
  # Returns nil if obj is nil, otherwise calls method
  def compile_safe_callm(scope, ob, method, args, block = nil)
    # With arguments and/or a block, the parser nests the call in the method slot:
    #   a&.m        => [:safe_callm, a, :m]                     (bare symbol; args/block nil)
    #   a&.m(x)     => [:safe_callm, a, [:call, :m, [x]]]       (args in the :call node, outer args nil)
    #   a&.m { }    => [:safe_callm, a, [:call, :m, [], [:do]]] (block in the :call node too)
    # Destructure so compile_callm receives a real method name plus the argument list and block;
    # otherwise the whole [:call, ...] node was passed as the "method name" -> SIGSEGV.
    if method.is_a?(Array) && method[0] == :call
      args   = method[2] if args.nil?
      block  = method[3] if block.nil?
      method = method[1]
    end

    @e.comment(Emitter::COMMENTS && "safe_callm #{ob.to_s}&.#{method.to_s} START")

    # Generate labels
    end_label = @e.get_local
    nil_label = @e.get_local

    # Evaluate the object
    ret = compile_eval_arg(scope, ob)
    @e.save_result(ret)

    # Check if nil (nil is a global label in this compiler)
    @e.cmpl("nil", :eax)
    @e.je(nil_label)

    # Not nil - call the method normally
    compile_callm(scope, ob, method, args, block)
    @e.jmp(end_label)

    # Was nil - return nil
    @e.local(nil_label)
    @e.movl("nil", :eax)

    @e.local(end_label)
    @e.comment(Emitter::COMMENTS && "safe_callm #{ob.to_s}&.#{method.to_s} END")

    return Value.new([:subexpr], :object)
  end

end
