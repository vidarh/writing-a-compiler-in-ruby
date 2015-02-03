#!/bin/env ruby

require 'set'

$: << File.dirname(__FILE__)

require 'emitter'
require 'parser'
require 'scope'
require 'function'
require 'extensions'
require 'ast'
require 'transform'
require 'print_sexp'

require 'compile_arithmetic'
require 'compile_comparisons'
require 'compile_calls'
require 'compile_class'
require 'compile_control'

require 'trace'
require 'stackfence'
require 'saveregs'
require 'splat'
require 'value'
require 'output_functions'
require 'globals'

require 'debugscope'

class Compiler
  attr_reader :global_functions, :global_scope
  attr_writer :trace, :stackfence

  # list of all predefined keywords with a corresponding compile-method
  # call & callm are ignored, since their compile-methods require
  # a special calling convention
  @@keywords = Set[
                   :do, :class, :defun, :defm, :if, :lambda,
                   :assign, :while, :index, :bindex, :let, :case, :ternif,
                   :hash, :return,:sexp, :module, :rescue, :incr, :block,
                   :required, :add, :sub, :mul, :div, :eq, :ne,
                   :lt, :le, :gt, :ge,:saveregs, :and, :or,
                   :preturn, :proc, :stackframe, :deref
                  ]

  Keywords = @@keywords

  @@oper_methods = Set[ :<< ]

  def initialize emitter = Emitter.new
    @e = emitter
    @global_functions = Globals.new
    @string_constants = {}
    @global_constants = Set.new
    @global_constants << :false
    @global_constants << :true
    @global_constants << :nil
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
    Value.new(get_arg(scope,[:sexp,[:call,:__get_symbol, sym.to_s]]),:object)
  end

  # For our limited typing we will in some cases need to do proper lookup.
  # For now, we just want to make %s(index __env__ xxx) mostly treated as
  # objects, in order to ensure that variables accesses that gets rewritten
  # to indirect via __env__ gets treated as object. The exception is
  # for now __env__[0] which contains a stackframe pointer used by
  # :preturn.
  def lookup_type(var, index = nil)
    (var == :__env__ && index != 0) ? :object : nil
  end

  # Returns an argument with its type identifier.
  #
  # If an Array is given, we have a subexpression, which needs to be compiled first.
  # If a Fixnum is given, it's an int ->   [:int, a]
  # If it's a Symbol, its a variable identifier and needs to be looked up within the given scope.
  # Otherwise, we assume it's a string constant and treat it like one.
  def get_arg(scope, a, save = false)
    return compile_exp(scope, a) if a.is_a?(Array)
    return get_arg(scope,:true, save) if a == true 
    return get_arg(scope,:false, save) if a == false
    return Value.new([:int, a]) if (a.is_a?(Fixnum))
    return Value.new([:int, a.to_i]) if (a.is_a?(Float)) # FIXME: uh. yes. This is a temporary hack
    return Value.new([:int, a.to_s[1..-1].to_i]) if (a.is_a?(Symbol) && a.to_s[0] == ?$) # FIXME: Another temporary hack
    if (a.is_a?(Symbol))
      name = a.to_s
      return intern(scope,name[1..-1]) if name[0] == ?:

      arg = scope.get_arg(a)

      # If this is a local variable or argument, we either
      # obtain the argument it is cached in, or we cache it
      # if possible. If we are calling #get_arg to get
      # a target to *save* a value to (assignment), we need
      # to mark it as dirty to ensure we save it back to memory
      # (spill it) if we need to evict the value from the
      # register to use it for something else.

      if arg.first == :lvar || arg.first == :arg || (arg.first == :global && arg.last == :self)
        reg = @e.cache_reg!(name, arg.first, arg.last, save)
        # FIXME: Need to check type

        return Value.new([:reg,reg],:object) if reg
      end

      # FIXME: Check type
      return Value.new(arg, :object)
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
    return Value.new([:addr,lab])
  end

  # Outputs all constants used within the code generated so far.
  # Outputs them as string and global constants, respectively.
  def output_constants
    @e.rodata { @string_constants.each { |c, l| @e.string(l, c) } }
    @e.bss    { @global_constants.each { |c|    @e.bsslong(c) }}
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

    cleaned = name.to_s.gsub(Regexp.new('>=|<=|==|[\?!<>+\-\/\*]')) do |match|
      dict[match.to_s]
    end

    cleaned = cleaned.split(Regexp.new('')).collect do |c|
      if c.match(Regexp.new('[a-zA-Z0-9_]'))
        c
      else
        "__#{c[0].ord.to_s(16)}"
      end
    end.join
    return cleaned
  end

  # Handle e.g. Tokens::Atom, which is parsed as (deref Tokens Atom)
  #
  # For now we are assuming statically resolvable chains, and not
  # tested multi-level dereference (e.g. Foo::Bar::Baz)
  #
  def compile_deref(scope, left, right)
    cscope = scope.find_constant(left)
    if !cscope || !cscope.is_a?(ClassScope)
      global_scope.dump
      error("Unable to resolve: #{left}::#{right} statically (FIXME)",scope) 
    end
    get_arg(cscope,right)
  end


  # Compiles a function definition.
  # Takes the current scope, in which the function is defined,
  # the name of the function, its arguments as well as the body-expression that holds
  # the actual code for the function's body.
  #
  # Note that compile_defun is now only accessed via s-expressions
  def compile_defun(scope, name, args, body)
    f = Function.new(name,args, body,scope)
    name = clean_method_name(name)

    # add function to the global list of functions defined so far
    name = @global_functions.set(name,f)

    # a function is referenced by its name (in assembly this is a label).
    # wherever we encounter that name, we really need the adress of the label.
    # so we mark the function with an adress type.
    return Value.new([:addr, clean_method_name(name)])
  end

  def compile_rescue(scope, *args)
    warning("RESCUE is NOT IMPLEMENTED")
    Value.new([:subexpr])
  end

  def compile_incr(scope, left, right)
    compile_exp(scope, [:assign, left, [:add, left, right]])
  end

  # Shortcircuit 'left && right' is equivalent to 'if left; right; end'
  def compile_and scope, left, right
    compile_if(scope, left, right)
  end


  def combine_types(left, right)
    type = nil
    if left && (!right || left.type == right.type)
      type = left.type
    end
    return Value.new([:subexpr],type)
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

    return Value.new([:subexpr])
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


  def compile_stackframe(scope)
    @e.comment("Stack frame")
    Value.new([:reg,:ebp])
  end

  # "Special" return for `proc` and bare blocks
  # to exit past Proc#call.
  def compile_preturn(scope, arg = nil)
    @e.comment("preturn")

    @e.save_result(compile_eval_arg(scope, arg)) if arg
    @e.pushl(:eax)

    # We load the return address pre-saved in __stackframe__ on creation of the proc.
    # __stackframe__ is automatically added to __env__ in `rewrite_let_env`

    ret = compile_eval_arg(scope,[:index,:__env__,0])

    @e.movl(ret,:ebp)
    @e.popl(:eax)
    @e.leave
    @e.ret
    @e.evict_all
    return Value.new([:subexpr])
  end

  # To compile `proc`, and anonymous blocks
  # See also #compile_lambda
  def compile_proc(scope, args=nil, body=nil)
    e = @e.get_local
    body ||= []
    args ||= []

    r = compile_defun(scope, e, [:self,:__closure__]+args,[:let,[]]+body)
    r
  end


  # Compiles and evaluates a given argument within a given scope.
  def compile_eval_arg(scope, arg)
    if arg.respond_to?(:position) && arg.position != nil
      pos = arg.position.inspect
      if pos != @lastpos
        @e.lineno(arg.position)
        trace(arg.position,arg)
      end
      @lastpos = pos
    end
    args = get_arg(scope,arg)
    error("Unable to find '#{arg.inspect}'") if !args
    atype = args[0]
    aparam = args[1]
    if atype == :ivar
      ret = compile_eval_arg(scope, :self)
      @e.load_instance_var(ret, aparam)
      # FIXME: Verify type of ivar
      return Value.new(@e.result_value, :object)
    elsif atype == :possible_callm
      return Value.new(compile_eval_arg(scope,[:callm,:self,aparam,[]]), :object)
    end

    return Value.new(@e.load(atype, aparam), args.type)
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

    @e.pushl(source) if source.is_a?(Symbol) # Register

    args = get_arg(scope,left,:save)
    atype = args[0]  # FIXME: Ugly, but the compiler can't yet compile atype,aparem = get_arg ...
    aparam = args[1]
    atype = :addr if atype == :possible_callm
    @e.popl(source) if source.is_a?(Symbol)

    if atype == :addr
      scope.add_constant(aparam)
      prefix = scope.name
      aparam = prefix + "__" + aparam.to_s if !prefix.empty?
      @global_constants << aparam
    elsif atype == :ivar
      # FIXME:  The register allocation here
      # probably ought to happen in #save_to_instance_var
      @e.pushl(source)
      ret = compile_eval_arg(scope, :self)
      @e.with_register do |reg|
        @e.popl(reg)
        @e.save_to_instance_var(reg, ret, aparam)
      end
      # FIXME: Need to check for "special" ivars
      return Value.new([:subexpr], :object)
    end

    if !(@e.save(atype, source, aparam))
      err_msg = "Expected an argument on left hand side of assignment - got #{atype.to_s}, (left: #{left.inspect}, right: #{right.inspect})"
      error(err_msg, scope, [:assign, left, right]) # pass current expression as well
    end
    return Value.new([:subexpr], :object)
  end


  # Compiles a do-end block expression.
  def compile_do(scope, *exp)
    if exp.length == 0
      exp = [:nil]
    end

    exp.each { |e| source=compile_eval_arg(scope, e); @e.save_result(source); }
    return Value.new([:subexpr])
  end

  # :sexp nodes are just aliases for :do nodes except
  # that code that rewrites the tree and don't want to
  # affect %s() escaped code should avoid descending
  # into :sexp nodes.
  def compile_sexp(scope, *exp)
    # We explicitly delete the type information for :sexp nodes for now.
    Value.new(compile_do(SexpScope.new(scope), *exp), nil)
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


  # Compiles an 8-bit array indexing-expression.
  # Takes the current scope, the array as well as the index number to access.
  def compile_bindex(scope, arr, index)
    source = compile_eval_arg(scope, arr)
    @e.pushl(source)
    source = compile_eval_arg(scope, index)
    r = @e.with_register do |reg|
      @e.popl(reg)
      @e.save_result(source)
      @e.addl(@e.result_value, reg)
    end
    return Value.new([:indirect8, r])
  end

  # Compiles a 32-bit array indexing-expression.
  # Takes the current scope, the array as well as the index number to access.
  def compile_index(scope, arr, index)
    source = compile_eval_arg(scope, arr)
    r = @e.with_register do |reg|
      @e.movl(source, reg)
      @e.pushl(reg)
      
      source = compile_eval_arg(scope, index)
      @e.save_result(source)
      @e.sall(2, @e.result_value)
      @e.popl(reg)
      @e.addl(@e.result_value, reg)
    end
    return Value.new([:indirect, r], lookup_type(arr,index))
  end



  def let(scope,*varlist)
    vars = Hash[*(varlist.zip(1..varlist.size)).flatten]
    lscope =LocalVarScope.new(vars, scope)
    if varlist.size > 0
      @e.evict_regs_for(varlist)
      @e.with_local(vars.size) do
        yield(lscope)
      end
      @e.evict_regs_for(varlist)
    else
      yield(lscope)
    end
  end


  # Compiles a let expression.
  # Takes the current scope, a list of variablenames as well as a list of arguments.
  def compile_let(scope, varlist, *args)
    let(scope, *varlist) do |ls|
      compile_do(ls, *args)
    end
    return Value.new([:subexpr])
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
    return Value.new([:subexpr]) if !exp || exp.size == 0

    pos = exp.position rescue nil
    @e.lineno(pos) if pos
    trace(pos,exp)

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
    return Value.new([:subexpr])
  end


  # Compiles the main function, where the compiled programm starts execution.
  def compile_main(exp)
    @e.main(exp.position.filename) do
      # We should allow arguments to main
      # so argc and argv get defined, but
      # that is for later.
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

    @vtableoffsets.vtable.each do |name, off|
      @e.emit(".equ   __voff__#{clean_method_name(name)}, #{off*4}")
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
      res = compile_eval_arg(@global_scope, ":#{name.to_s}".to_sym)
      @e.with_register do |reg|
        @e.popl(reg)
        @e.pushl(res)
        @e.pushl(reg)
      end
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

require "driver" if __FILE__ == $0
