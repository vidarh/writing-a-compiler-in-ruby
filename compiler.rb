#!/bin/env ruby

require 'emitter'
require 'parser'
require 'scope'
require 'function'
require 'extensions'
require 'ast'
require 'transform'
require 'set'
require 'print_sexp'

class Compiler
  attr_reader :global_functions
  attr_accessor :trace

  # list of all predefined keywords with a corresponding compile-method
  # call & callm are ignored, since their compile-methods require
  # a special calling convention
  @@keywords = Set[
                   :do, :class, :defun, :defm, :if, :lambda,
                   :assign, :while, :index, :let, :case, :ternif,
                   :hash, :return,:sexp, :module, :rescue, :incr, :block,
                   :required
                  ]

  Keywords = @@keywords

  @@oper_methods = Set[ :<< ]

  def initialize emitter = Emitter.new
    @e = emitter
    @global_functions = {}
    @string_constants = {}
    @global_constants = Set.new
    @classes = {}
    @vtableoffsets = VTableOffsets.new
    @trace = false
  end


  # Outputs nice compiler error messages, similar to
  # the parser (ParserBase#error).
  def error(error_message, current_scope = nil, current_exp = nil)
    if current_exp.respond_to?(:position) && current_exp.position && current_exp.position.lineno
      pos = current_exp.position
      location = " @ #{pos.inspect}"
    elsif @lastpos
      location = " near (after) #{@lastpos}"
    else
      location = ""
    end
    raise "Compiler error: #{error_message}#{location}\n
           current scope: #{current_scope.inspect}\n
           current expression: #{current_exp.inspect}\n"
  end


  # Prints out a warning to the console.
  # Similar to error, but doesn't throw an exception, only prints out a message
  # and any given additional arguments during compilation process to the console.
  def warning(warning_message, *args)
    STDERR.puts("#{warning_message} - #{args.join(',')}")
  end


  # Allocate a symbol
  def intern(scope,sym)
    # FIXME: Do this once, and add an :assign to a global var, and use that for any
    # later static occurrences of symbols.
    get_arg(scope,[:sexp,[:call,:__get_symbol, sym.to_s]])
  end

  # Returns an argument with its type identifier.
  #
  # If an Array is given, we have a subexpression, which needs to be compiled first.
  # If a Fixnum is given, it's an int ->   [:int, a]
  # If it's a Symbol, its a variable identifier and needs to be looked up within the given scope.
  # Otherwise, we assume it's a string constant and treat it like one.
  def get_arg(scope, a)
    return compile_exp(scope, a) if a.is_a?(Array)
    return [:int, a] if (a.is_a?(Fixnum))
    return [:int, a.to_i] if (a.is_a?(Float)) # FIXME: uh. yes. This is a temporary hack
    return [:int, a.to_s[1..-1].to_i] if (a.is_a?(Symbol) && a.to_s[0] == ?$) # FIXME: Another temporary hack
    if (a.is_a?(Symbol))
      name = a.to_s
      return intern(scope,name.rest) if name[0] == ?:
      return scope.get_arg(a)
    end

    warning("nil received by get_arg") if !a
    return strconst(a)
  end

  def strconst(a)
    lab = @string_constants[a]
    if !lab # For any constants in s-expressions
      lab = @e.get_local
      @string_constants[a] = lab
    end
    return [:addr,lab]
  end

  # Outputs all constants used within the code generated so far.
  # Outputs them as string and global constants, respectively.
  def output_constants
    @e.rodata { @string_constants.each { |c, l| @e.string(l, c) } }
    @e.bss    { @global_constants.each { |c|    @e.bsslong(c) }}
  end


  # Similar to output_constants, but for functions.
  # Compiles all functions, defined so far and outputs the appropriate assembly code.
  def output_functions
    # This is a bit ugly, but handles the case of lambdas or inner
    # functions being added during the compilation... Should probably
    # refactor.
    while f = @global_functions.shift
      name = f[0]
      func = f[1]
      # create a function scope for each defined function and compile it appropriately.
      # also pass it the current global scope for further lookup of variables used
      # within the functions body that aren't defined there (global variables and those,
      # that are defined in the outer scope of the function's)

      # FIXME: Would it be better to output these grouped by source file?
      if func.body.is_a?(AST::Expr)
        @e.include(func.body.position.filename) do
          @e.func(name, func.rest?, func.body.position) { compile_eval_arg(FuncScope.new(func), func.body) }
        end
      else
        @e.func(name, func.rest?, nil) { compile_eval_arg(FuncScope.new(func), func.body) }
      end
    end
  end

  # Need to clean up the name to be able to use it in the assembler.
  # Strictly speaking we don't *need* to use a sensible name at all,
  # but it makes me a lot happier when debugging the asm.
  def clean_method_name(name)
    dict = {
      "?" => "__Q",     "!"  => "__X", 
      "[]" => "__NDX",  "==" => "__eq",  
      ">=" => "__ge",   "<=" => "__le", 
      "<"  => "__lt",   ">"  => "__gt",
      "/"  => "__div",  "*"  => "__mul",
      "+"  => "__plus", "-"  => "__minus"}

    cleaned = name.to_s.gsub />=|<=|==|[\?!=<>+\-\/\*]/ do |match|
      dict[match.to_s]
    end

    cleaned = cleaned.split(//).collect do |c|
      if c.match(/[a-zA-Z0-9_]/)
        c
      else
        "__#{c[0].to_s(16)}"
      end
    end.join
    return cleaned
  end


  # Compiles a function definition.
  # Takes the current scope, in which the function is defined,
  # the name of the function, its arguments as well as the body-expression that holds
  # the actual code for the function's body.
  #
  # Note that compile_defun is now only accessed via s-expressions
  def compile_defun(scope, name, args, body)
    f = Function.new(args, body,scope)
    name = clean_method_name(name)

    # add function to the global list of functions defined so far
    @global_functions[name] = f

    # a function is referenced by its name (in assembly this is a label).
    # wherever we encounter that name, we really need the adress of the label.
    # so we mark the function with an adress type.
    return [:addr, clean_method_name(name)]
  end

  # Compiles a method definition and updates the
  # class vtable.
  def compile_defm(scope, name, args, body)
    scope = scope.class_scope

    # FIXME: Replace "__closure__" with the block argument name if one is present
    f = Function.new([:self,:__closure__]+args, body, scope) # "self" is "faked" as an argument to class methods

    @e.comment("method #{name}")

    body.depth_first do |exp|
      exp.each do |n| 
        scope.add_ivar(n) if n.is_a?(Symbol) and n.to_s[0] == ?@ && n.to_s[1] != ?@
      end
    end

    cleaned = clean_method_name(name)
    fname = "__method_#{scope.name}_#{cleaned}"
    scope.set_vtable_entry(name, fname, f)

    # Save to the vtable.
    v = scope.vtable[name]
    compile_eval_arg(scope,[:sexp, [:call, :__set_vtable, [:self,v.offset, fname.to_sym]]])
    
    # add the method to the global list of functions defined so far
    # with its "munged" name.
    @global_functions[fname] = f
    
    # This is taken from compile_defun - it does not necessarily make sense for defm
    return [:addr, clean_method_name(fname)]
  end

  # Compiles an if expression.
  # Takes the current (outer) scope and two expressions representing
  # the if and else arm.
  # If no else arm is given, it defaults to nil.
  def compile_if(scope, cond, if_arm, else_arm = nil)
    compile_eval_arg(scope, cond)
    l_else_arm = @e.get_local
    l_end_if_arm = @e.get_local
    @e.jmp_on_false(l_else_arm)
    compile_eval_arg(scope, if_arm)
    @e.jmp(l_end_if_arm) if else_arm
    @e.local(l_else_arm)
    compile_eval_arg(scope, else_arm) if else_arm
    @e.local(l_end_if_arm) if else_arm
    return [:subexpr]
  end

  def compile_return(scope, arg = nil)
    compile_eval_arg(scope, arg) if arg
    @e.leave
    @e.ret
    [:subexpr]
  end

  def compile_rescue(scope, *args)
    warning("RESCUE is NOT IMPLEMENTED")
    [:subexpr]
  end

  def compile_incr(scope, left, right)
    compile_exp(scope, [:assign, left, [:add, left, right]])
  end

  # Compiles the ternary if form (cond ? then : else) 
  # It may be better to transform this into the normal
  # if form in the tree.
  def compile_ternif(scope, cond, alt)
    if alt.is_a?(Array) && alt[0] == :ternalt
      if_arm = alt[1]
      else_arm = alt[2]
    else
      if_arm = alt
    end
    compile_if(scope,cond,if_arm,else_arm)
  end

  def compile_hash(scope, *args)
    pairs = []
    args.collect do |pair|
      if !pair.is_a?(Array) || pair[0] != :pair
        error("Literal Hash must contain key value pairs only",scope,args)
      end
      pairs << pair[1]
      pairs << pair[2]
    end
    compile_callm(scope, :Hash, :new, pairs)
  end

  def compile_case(scope, *args)
#    error(":case not implemented yet", scope, [:case]+args)
    # FIXME:
    # Implement like this: compile_eval_arg
    # save the register, and loop over the "when"'s.
    # Compile each of the "when"'s as "if"'s where the value
    # is loaded from the stack and compared with the value
    # (or values) in the when clause


    # experimental (need to look into saving to register etc..):
    # but makes it compile all the way through for now...

    @e.comment("compiling case expression")
    compare_exp = args.first

    @e.comment("compare_exp: #{compare_exp}")

    args.rest.each do |whens|
      whens.each do |exp| # each when-expression
        test_value = exp[1] # value to test against
        body = exp[2] # body to be executed, if compare_exp === test_value

        @e.comment("test_value: #{test_value.inspect}")
        @e.comment("body: #{body.inspect}")

        # turn case-expression into if.
        compile_if(scope, [:callm, compare_exp, :===, test_value], body)
      end
    end

    return [:subexpr]
  end

  # Compiles an anonymous function ('lambda-expression').
  # Simply calls compile_defun, only, that the name gets generated
  # by the emitter via Emitter#get_local.
  def compile_lambda(scope, args=nil, body=nil)
    e = @e.get_local
    body ||= []
    args ||= []
    # FIXME: Need to use a special scope object for the environment,
    # including handling of self. 
    # Note that while compiled with compile_defun, the calling convetion
    # is that of a method. However we have the future complication of
    # handling instance variables in closures, which is rather painful.
    r = compile_defun(scope, e, [:self,:__closure__]+args,[:let,[]]+body)
    r
  end


  # Compiles and evaluates a given argument within a given scope.
  def compile_eval_arg(scope, arg)
    if arg.respond_to?(:position) && arg.position != nil
      pos = arg.position.inspect
      if pos != @lastpos
        @e.lineno(arg.position)
        if @trace
          compile_exp(scope,[:call,:puts,arg.position.inspect])
        end
      end
      @lastpos = pos
    end
    args = get_arg(scope,arg)
    atype = args[0]
    aparam = args[1]
    if atype == :ivar
      ret = compile_eval_arg(scope, :self)
      @e.load_instance_var(ret, aparam)
      return @e.result_value
    elsif atype == :possible_callm
      return compile_eval_arg(scope,[:callm,:self,aparam,[]])
    end
    return @e.load(atype, aparam)
  end


  # Compiles an assignment statement.
  def compile_assign(scope, left, right)
    # transform "foo.bar = baz" into "foo.bar=(baz) - FIXME: Is this better handled in treeoutput.rb?
    # Also need to handle :call equivalently.
    if left.is_a?(Array) && left[0] == :callm && left.size == 3 # no arguments
      return compile_callm(scope, left[1], (left[2].to_s + "=").to_sym, right)
    end

    source = compile_eval_arg(scope, right)
    atype = nil
    aparam = nil
    @e.save_register(source) do
      args = get_arg(scope,left)
      atype = args[0]  # FIXME: Ugly, but the compiler can't yet compile atype,aparem = get_arg ...
      aparam = args[1]
      atype = :addr if atype == :possible_callm
    end

    if atype == :addr
      @global_scope.globals << aparam
      @global_constants << aparam
    elsif atype == :ivar
      # FIXME:  The register allocation here
      # probably ought to happen in #save_to_instance_var
      @e.with_register do |reg|
        @e.movl(source,reg)
        ret = compile_eval_arg(scope, :self)
        @e.save_to_instance_var(reg, ret, aparam)
      end
      return [:subexpr]
    end

    if !(@e.save(atype, source, aparam))
      err_msg = "Expected an argument on left hand side of assignment - got #{atype.to_s}, (left: #{left.inspect}, right: #{right.inspect})"
      error(err_msg, scope, [:assign, left, right]) # pass current expression as well
    end
    return [:subexpr]
  end


  # Compiles a function call.
  # Takes the current scope, the function to call as well as the arguments
  # to call the function with.
  def compile_call(scope, func, args, block = nil)
    return compile_yield(scope, args, block) if func == :yield

    # This is a bit of a hack. get_arg will also be called from
    # compile_eval_arg below, but we need to know if it's a callm
    fargs = get_arg(scope, func)

    return compile_callm(scope,:self, func, args,block) if fargs && fargs[0] == :possible_callm

    args = [args] if !args.is_a?(Array)
    @e.with_stack(args.length, true) do
      args.each_with_index do |a, i|
        param = compile_eval_arg(scope, a)
        @e.save_to_stack(param, i)
      end
      @e.call(compile_eval_arg(scope, func))
    end
    return [:subexpr]
  end

  # If adding type-tagging, this is the place to do it
  # self_reg and dest_reg *can* be the same.
  # In the case of type tagging, the self_reg value
  # would be matched against the suitable type tags
  # to determine the class, instead of loading the class
  # from the first long of the object.
  def load_class self_reg, dest_reg
    @e.load_indirect(self_reg, dest_reg)  # self.class
  end

  # compile_yield
  # Yield to the supplied block
  def compile_yield(scope, args, block)
    @e.comment("yield begin")
    args ||= []
    args = [args] if !args.is_a?(Array) # FIXME: It's probably better to make the parser consistently pass an array
    args = [0] + args # FIXME: No chaining of blocks. Is chaining of blocks legal? Never used it. Anyway, we don't support it

    compile_callm_args(scope, :self, args) do
      reg = @e.load(:arg, 1) # The block parameter
      @e.call(reg)
    end
    @e.comment("yield end")
    return [:subexpr]
  end

  def handle_splat(scope,args)
    # FIXME: Quick and dirty splat handling:
    # - If the last node has a splat, we cheat and assume it's
    #   from the arguments rather than a proper Ruby Array.
    # - We assume we can just allocate args.length+1+numargs
    # - We wastefully do it in two rounds and muck directly
    #   with %esp for now until I figure out how to do this
    #   more cleanly.
    splat = args.last.is_a?(Array) && args.last.first == :splat

    return nil if !splat

    # FIXME: This is just a disaster waiting to happen
    # (needs proper register allocation)
    @e.comment("*#{args.last.last.to_s}")
    reg = compile_eval_arg(scope,:numargs)
    @e.sall(2,reg)
    @e.subl(reg,:esp)
    @e.movl(reg,:edx)
    reg = compile_eval_arg(scope,args.last.last)
    @e.addl(reg,:edx)
    @e.movl(:esp,:ecx)
    l = @e.local
    @e.movl("(%eax)",:ebx)
    @e.movl(:ebx,"(%ecx)")
    @e.addl(4,:eax)
    @e.addl(4,:ecx)
    @e.cmpl(reg,:edx)
    @e.jne(l)
    @e.subl(:esp,:ecx)
    @e.sarl(2,:ecx)
    @e.comment("*#{args.last.last.to_s} end")

    return args[0..-2]
  end

  def compile_callm_args(scope, ob, args)
    splat = handle_splat(scope,args)
    args = splat if splat

    @e.with_stack(args.length+1, true) do
      if splat
        @e.addl(:ecx,:ebx)
      end

      ret = compile_eval_arg(scope, ob)
      @e.save_to_stack(ret, 0)
      args.each_with_index do |a,i|
        param = compile_eval_arg(scope, a)
        @e.save_to_stack(param, i+1)
      end

      # This is where the actual call gets done
      # This differs depending on whether it's a normal
      # method call or a closure call.
      yield
    end

    if splat
      reg = compile_eval_arg(scope,:numargs)
      @e.sall(2,reg)
      @e.addl(reg,:esp)
    end
  end
  

  # Compiles a method call to an object.
  # Similar to compile_call but with an additional object parameter
  # representing the object to call the method on.
  # The object gets passed to the method, which is just another function,
  # as the first parameter.
  def compile_callm(scope, ob, method, args, block = nil)
    # FIXME: Shouldn't trigger - probably due to the callm rewrites
    return compile_yield(scope, args, block) if method == :yield and ob == :self

    @e.comment("callm #{ob.inspect}.#{method.inspect}")

    args ||= []
    args = [args] if !args.is_a?(Array) # FIXME: It's probably better to make the parser consistently pass an array

    args = [block ? block : 0] + args

    off = @vtableoffsets.get_offset(method)
    if !off
      # Argh. Ok, then. Lets do send
      off = @vtableoffsets.get_offset(:__send__)
      args = [":#{method}".to_sym] + args
      warning("WARNING: No vtable offset for '#{method}' -- you're likely to get a method_missing")
      #error(err_msg, scope, [:callm, ob, method, args])
    end

    compile_callm_args(scope, ob, args) do
      @e.with_register do |reg|
        @e.load_indirect(:esp, reg) # self
        load_class(reg,reg)
        @e.movl("#{off*Emitter::PTR_SIZE}(%#{reg.to_s})", @e.result_value)
        @e.call(@e.result_value)
      end
    end

    @e.comment("callm #{ob.to_s}.#{method.to_s} END")
    return [:subexpr]
  end


  # Compiles a do-end block expression.
  def compile_do(scope, *exp)
    exp.each { |e| source=compile_eval_arg(scope, e); @e.save_result(source); }
    return [:subexpr]
  end

  # :sexp nodes are just aliases for :do nodes except
  # that code that rewrites the tree and don't want to
  # affect %s() escaped code should avoid descending
  # into :sexp nodes.
  def compile_sexp(scope, *exp)
    compile_do(SexpScope.new(scope), *exp)
  end

  # :block nodes are "begin .. end" blocks or "do .. end" blocks
  # (which doesn't really matter to the compiler, just the parser
  # - what matters is that if it stands on it's own it will be
  # "executed" immediately; otherwise it should be treated like
  # a :lambda more or less. 
  #
  # FIXME: Since we don't implement "rescue" yet, we'll just
  # treat it as a :do, which is likely to cause lots of failures
  def compile_block(scope, *exp)
    compile_do(scope, *exp[1])
  end


  # Compiles a array indexing-expression.
  # Takes the current scope, the array as well as the index number to access.
  def compile_index(scope, arr, index)
    source = compile_eval_arg(scope, arr)
    reg = nil #This is needed to retain |reg|
    @e.with_register do |reg|
      @e.movl(source, reg)
      source = compile_eval_arg(scope, index)
      @e.save_result(source)
      @e.sall(2, @e.result_value)
      @e.addl(@e.result_value, reg)
    end
    return [:indirect, reg]
  end


  # Compiles a while loop.
  # Takes the current scope, a condition expression as well as the body of the function.
  def compile_while(scope, cond, body)
    @e.loop do |br|
      var = compile_eval_arg(scope, cond)
      @e.jmp_on_false(br)
      compile_exp(scope, body)
    end
    return [:subexpr]
  end

  # Compiles a let expression.
  # Takes the current scope, a list of variablenames as well as a list of arguments.
  def compile_let(scope, varlist, *args)
    vars = {}
    varlist.each_with_index {|v, i| vars[v]=i}
    ls = LocalVarScope.new(vars, scope)
    if vars.size > 0
      @e.with_local(vars.size) { compile_do(ls, *args) }
    else
      compile_do(ls, *args)
    end
    return [:subexpr]
  end

  def compile_module(scope,name, *exps)
    # FIXME: This is a cop-out that will cause horrible
    # crashes - they are not the same (though nearly)
    compile_class(scope,name, *exps)
  end

  # Compiles a class definition.
  # Takes the current scope, the name of the class as well as a list of expressions
  # that belong to the class.
  def compile_class(scope, name,superclass, *exps)
    @e.comment("=== class #{name} ===")

    cscope = ClassScope.new(scope, name, @vtableoffsets)

    # FIXME: Need to be able to handle re-opening of classes
    exps.each do |l2|
      l2.each do |e|
        if e.is_a?(Array) 
          if e[0] == :defm
            cscope.add_vtable_entry(e[1]) # add method into vtable of class-scope to associate with class
          elsif e[0] == :call && e[1] == :attr_accessor
            # This is a bit presumptious, assuming noone are stupid enough to overload
            # attr_accessor, attr_reader without making them do more or less the same thing.
            # but the right thing to do is actually to call the method.
            #
            # In any case there is no actual harm in allocating the vtable
            # entry.`
            #
            # We may do a quick temporary hack to synthesize the methods,
            # though, as otherwise we need to implement the full define_method
            # etc.
            arr = e[1].is_a?(Array) ? e[2] : [e[2]]
            arr.each {|entry|
              cscope.add_vtable_entry(entry.to_s[1..-1].to_sym) 
            }
          end
        end
      end
    end
    @classes[name] = cscope
    @global_scope.globals << name
    sscope = name == superclass ? nil : @classes[superclass]
    ssize = sscope ? sscope.klass_size : nil
    ssize = 0 if ssize.nil?
    compile_exp(scope, [:assign, name.to_sym, [:sexp,[:call, :__new_class_object, [cscope.klass_size,superclass,ssize]]]])
    @global_constants << name

    compile_exp(cscope, [:assign, :@instance_size, cscope.instance_size])

    exps.each do |e|
      addr = compile_do(cscope, *e)
    end

    @e.comment("=== end class #{name} ===")
    return [:global, name]
  end

  # Put at the start of a required file, to allow any special processing
  # before/after 
  def compile_required(scope,exp)
    @e.include(exp.position.filename) do
      compile_exp(scope,exp)
    end
  end

  # General method for compiling expressions.
  # Calls the specialized compile methods depending of the
  # expression to be compiled (e.g. compile_if, compile_call, compile_let etc.).
  def compile_exp(scope, exp)
    return [:subexpr] if !exp || exp.size == 0

    if @trace
      @trace = false # A bit ugly, but prevents infinite recursion
      @e.comment(exp[0..1].inspect)
      compile_exp(scope,[:call,:puts,exp[0..1].inspect]) 
      @trace = true
    end

    @e.lineno(exp.position) if exp.respond_to?(:position) && exp.position

    # check if exp is within predefined keywords list
    if(@@keywords.include?(exp[0]))
      return self.send("compile_#{exp[0].to_s}", scope, *exp.rest)
    elsif @@oper_methods.member?(exp[0])
      return compile_callm(scope, exp[1], exp[0], exp[2..-1])
    else
      return compile_call(scope, exp[1], exp[2],exp[3]) if (exp[0] == :call)
      return compile_callm(scope, exp[1], exp[2], exp[3], exp[4]) if (exp[0] == :callm)
      return compile_call(scope, exp[0], exp.rest) if (exp.is_a? Array)
    end

    warning("Somewhere calling #compile_exp when they should be calling #compile_eval_arg? #{exp.inspect}")
    res = compile_eval_arg(scope, exp[0])
    @e.save_result(res)
    return [:subexpr]
  end


  # Compiles the main function, where the compiled programm starts execution.
  def compile_main(exp)
    @e.main(exp.position.filename) do
      # We should allow arguments to main
      # so argc and argv get defined, but
      # that is for later.
      @global_scope = GlobalScope.new(@vtableoffsets)
      compile_eval_arg(@global_scope, exp)
    end
  end


  # We need to ensure we find the maximum
  # size of the vtables *before* we compile
  # any of the classes
  #
  # Consider whether to check :call/:callm nodes as well, though they
  # will likely hit method_missing
  def alloc_vtable_offsets(exp)
    exp.depth_first(:defm) do |defun|
      @vtableoffsets.alloc_offset(defun[1])
      :skip
    end

    classes = 0
    exp.depth_first(:class) { |c| classes += 1; :skip }
    #warning("INFO: Max vtable offset when compiling is #{@vtableoffsets.max} in #{classes} classes, for a total vtable overhead of #{@vtableoffsets.max * classes * 4} bytes")
  end
  
  # When we hit a vtable slot for a method that doesn't exist for
  # the current object/class, we call method_missing. However, method
  # missing needs the symbol of the method that was being called.
  # 
  # To handle that, we insert the address of a "thunk" instead of
  # the real method missing. The thunk is a not-quite-function that
  # adjusts the stack to prepend the symbol matching the current
  # vtable slot and then jumps straight to __method_missing, instead
  # of wasting extra stack space and time on copying the objects.
  def output_vtable_thunks
    @vtableoffsets.vtable.each do |name,_|
      @e.label("__vtable_missing_thunk_#{clean_method_name(name)}")
      # FIXME: Call get_symbol for these during initalization
      # and then load them from a table instead.
      compile_eval_arg(@global_scope, ":#{name.to_s}".to_sym)
      @e.popl(:edx) # The return address
      @e.pushl(:eax)
      @e.pushl(:edx)
      @e.jmp("__method_missing")
    end
    @e.label("__base_vtable")
    # For ease of implementation of __new_class_object we
    # pad this with the number of class ivar slots so that the
    # vtable layout is identical as for a normal class
    ClassScope::CLASS_IVAR_NUM.times { @e.long(0) }
    @vtableoffsets.vtable.to_a.sort_by {|e| e[1] }.each do |e|
      @e.long("__vtable_missing_thunk_#{clean_method_name(e[0])}")
    end
  end

  # Starts the actual compile process.
  def compile exp
    alloc_vtable_offsets(exp)
    compile_main(exp)

    # after the main function, we ouput all functions and constants
    # used and defined so far.
    output_functions
    output_vtable_thunks
    output_constants
  end
end

if __FILE__ == $0
  dump = ARGV.include?("--parsetree")
  norequire = ARGV.include?("--norequire") # Don't process require's statically - compile them instead
  trace = ARGV.include?("--trace")
  transform = !ARGV.include?("--notransform")

  # Option to not rewrite the parse tree (breaks compilation, but useful for debugging of the parser)
  OpPrec::TreeOutput.dont_rewrite if ARGV.include?("--dont-rewrite")


  # check remaining arguments, if a filename is given.
  # if not, read from STDIN.
  input_source = STDIN
  ARGV.each do |arg|
    if File.exists?(arg)
      input_source = File.open(arg, "r")
      STDERR.puts "reading from file: #{arg}"
      break
    end
  end

  s = Scanner.new(input_source)
  prog = nil
  
  begin
    parser = Parser.new(s, {:norequire => norequire})
    prog = parser.parse
  rescue Exception => e
    STDERR.puts "#{e.message}"
    # FIXME: The position ought to come from the parser, as should the rest, since it could come
    # from a 'require'd file, in which case the fragment below means nothing.
    STDERR.puts "Failed at line #{s.lineno} / col #{s.col}  before:\n"
    buf = ""
    while s.peek && buf.size < 100
      buf += s.get
    end
    STDERR.puts buf
  end
  
  if prog
    c = Compiler.new
    c.trace = true if trace

    c.preprocess(prog) if transform

    if dump
      print_sexp prog
      exit
    end
    
    c.compile(prog)
  end
end
