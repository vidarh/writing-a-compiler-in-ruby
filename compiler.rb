#!/bin/env ruby

require 'set'

$: << File.dirname(__FILE__)

require 'emitter'
require 'parser'
require 'scope'
require 'eigenclassscope'
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
require 'compile_include'
require 'compile_pragma'

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
                   :do, :class, :defun, :defm, :if, :unless,
                   :assign, :while, :until, :index, :bindex, :let, :case, :ternif,
                   :hash, :return,:sexp, :module, :rescue, :incr, :decr, :block,
                   :required, :add, :sub, :mul, :div, :shl, :sar, :sarl, :sall, :eq, :ne,
                   :lt, :le, :gt, :ge,:saveregs, :and, :or,
                   :preturn, :stackframe, :stackpointer, :deref, :include, :addr,
                   :protected, :array, :splat, :mod, :or_assign, :break, :next, :alias,
                   :__compiler_internal, # See `compile_pragma.rb`
                   :__inline, # See `inline.rb`
                   :bitand, :bitor, :bitxor, # Bitwise operators
                   :mulfull, # Widening multiply - returns both low and high words
                  :div64, # 64-bit division - divides EDX:EAX by operand
                  :unwind # Exception stack unwinding
                  ]

  Keywords = @@keywords

  # Note: Only operators with full compilation support should be here
  # Bitwise operators (&, |, ^, ~, >>, **) are defined in operators.rb
  # but don't have compiler methods yet, so they're not included here
  @@oper_methods = Set[ :<< ]

  def initialize emitter = Emitter.new
    @e = emitter
    @global_functions = Globals.new
    @string_constants = {}
    @float_constants = {}  # Store float literals to emit in rodata
    @global_constants = Set.new
    @global_constants << :false
    @global_constants << :true
    @global_constants << :nil
    @classes = {}
    @vtableoffsets = VTableOffsets.new
    @trace = false

    @global_scope = nil
    @lastpos = nil
    @linelabel = 0
    @section = 0
  end


  # Outputs nice compiler error messages, similar to
  # the parser (ParserBase#error).
  def error(error_message, current_scope = nil, current_exp = nil)
    # Extract position information for CompilerError formatting
    filename = nil
    line = nil
    column = nil

    if current_exp.respond_to?(:position) && current_exp.position
      pos = current_exp.position
      filename = pos.filename if pos.respond_to?(:filename)
      line = pos.lineno if pos.respond_to?(:lineno)
      column = pos.col if pos.respond_to?(:col)
    end

    raise CompilerError.new(error_message, filename, line, column)
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
  # If a Fixnum is given, it's an int ->   [:int, a]
  # If it's a Symbol, its a variable identifier and needs to be looked up within the given scope.
  # Otherwise, we assume it's a string constant and treat it like one.
  def get_arg(scope, a, save = false)
    return compile_exp(scope, a) if a.is_a?(Array)
    return get_arg(scope,:true, save) if a == true
    return get_arg(scope,:false, save) if a == false
    return get_arg(scope,:nil, save) if a == nil
    return Value.new([:int, a]) if (a.is_a?(Integer))

    if a.is_a?(Float)
      # Allocate Float object and store the value
      # Generate a label for this float constant
      label = ".float_#{@float_constants.length}"
      @float_constants[label] = a
      # Use compile_exp to create the Float object
      ptr = compile_exp(scope, [:callm, :Float, :new])
      # Function calls return in %eax, so store the double there
      # Store the double value at offset 4 (after vtable pointer)
      @e.storedouble(:eax, 4, label)
      return ptr
    end

    if a == :"block_given?"
      return compile_exp(scope,
                         [:if,
                          [:ne, :__closure__, 0],
                          :true, :false])
    end

    if a == :"caller"
      return compile_exp(scope,
                         [:sexp, [:__get_string, "FIXME: caller not implemented yet"]])
    end
    arg = nil
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
    @e.rodata do
      @string_constants.each { |c, l| @e.string(l, c) }
      @float_constants.each do |label, value|
        @e.emit(label + ":")
        @e.emit(".double", value)
      end
    end

    # FIXME: Temporary workaround to add bss entries for "missing" globals
    vars = (@global_constants.to_a + @global_scope.globals.keys).collect{|s| s.to_s}.sort.uniq - ["__roots_start","__roots_end"]
    # Strip $ prefix from global variable names for assembly
    vars = vars.collect{|v| v[0] == ?$ ? v[1..-1] : v}
    @e.bss    do
      #@e.bsslong("__stack_top")
      @e.label("__roots_start")
      vars.each { |c|    @e.bsslong(c) }
      @e.label("__roots_end")
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
      "+"  => "__plus", "-"  => "__minus",
      "-@" => "__uminus", "+@" => "__uplus",
      "~"  => "__tilde"}

    pos = 0
    # FIXME: this is necessary because we
    # currently don't define Symbol#[]
    name = name.to_s
    len = name.length
    out = ""

    while (pos < len)
      c  = name[pos].chr
      co = c.ord
      pos += 1
      if (co >= ?a.ord &&
         co <= ?z.ord) ||
          (co >= ?A.ord &&
           co <= ?Z.ord) ||
          (co >= ?0.ord &&
           co <= ?9.ord) ||
          co == ?_.ord

        out << c
      else
        cn = name[pos]
        if cn
          ct = c + cn.chr
        else
          ct = nil
        end

        if dict[ct]
          out << dict[ct]
          pos += 1
        elsif dict[c]
          out << dict[c]
        else
          out << "__#{co.to_s(16)}"
        end
      end
    end
    out
  end

  # Handle e.g. Tokens::Atom, which is parsed as (deref Tokens Atom)
  #
  # For now we are assuming statically resolvable chains, and not
  # tested multi-level dereference (e.g. Foo::Bar::Baz)
  #
  def compile_deref(scope, left, right)
    cscope = scope.find_constant(left)
    if !cscope || !cscope.is_a?(ModuleScope)
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
  def compile_defun(scope, name, args, body, break_label = nil)
    raise "Internal error: Expecting a name; got #{name.inspect}" if name.is_a?(Array)

    f = Function.new(name,args, body, scope, break_label || @e.get_local, false)
    name = clean_method_name(name)

    # add function to the global list of functions defined so far
    name = @global_functions.set(name,f)

    # a function is referenced by its name (in assembly this is a label).
    # wherever we encounter that name, we really need the adress of the label.
    # so we mark the function with an adress type.
    return Value.new([:addr, clean_method_name(name)])
  end

  def compile_rescue(scope, rval, lval)
    # Note: rescue is now handled via compile_begin_rescue in compile_block
    # This method is kept for backwards compatibility but shouldn't be called
    compile_exp(scope,lval)
  end

  def compile_decr(scope, left, right)
    compile_assign(scope, left, [:callm, left, :-, [right]])
  end

  def compile_incr(scope, left, right)
    compile_assign(scope, left, [:callm, left, :+, [right]])
  end

  # Shortcircuit 'left && right' is equivalent to 'if left; right; end'
  def compile_and scope, left, right
    compile_if(scope, left, right)
  end


  def combine_types(left, right)
    type = nil
    if left
      if (!right || left.type == right.type)
        type = left.type
      end
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
    compile_callm(scope, :Hash, :[], pairs)
  end

  # FIXME: Compiler @bug: This method was a self-recursive
  # lambda in `#compile_case`
  def compile_case_test(compare_exp, test_exprs)
    test_value = test_exprs
    xrest = []
    if test_exprs.is_a?(Array)
      #STDERR.puts test_exprs.inspect
      if test_exprs[0] == :comma
        test_value = test_exprs[1]
        xrest = Array(test_exprs[2])
      end
      #STDERR.puts xrest.inspect
    end
    cmp = [:callm, test_value, :===, [compare_exp]]

    if xrest.empty?
      cmp
    else
      [:or, cmp, compile_case_test(compare_exp, xrest)]
    end
  end

  # FIXME: This is unsafe. It only works for the compiler
  # for now because none of the case expressions in the
  # compiler itself have side effects.
  def compile_whens(compare_exp, whens)
    exp = whens.first

    if exp[0] == :when
      test_values = exp[1]

      body = exp[2] # body to be executed, if compare_exp === test_value

      @e.comment("test_value: #{test_values.inspect}")
      @e.comment("body: #{body.inspect}")

      xrest = whens.slice(1..-1)
      if xrest.empty?
        xrest = [:do]
      else
        xrest = compile_whens(compare_exp, xrest)
      end
      [:do, [:if, compile_case_test(compare_exp, test_values), [:do]+body, xrest]]
    else
      [:do]+exp
    end
  end

  def compile_case(scope, *args)
    # FIXME: Compiler @bug:
    # The `xrest`'s below were `rest` but that causes `rest` in the
    # expression `arg.rest` to be misinterpreted during rewrite to
    # method call relative to the contents of the `rest` variable,
    # which needless to say is a total disaster.
    #
    # Further, there is likely another problem here, in that it looks like
    # a single, shared, environment is created for the two lambdas, but that
    # may be unavoidable given Ruby semantics.

    # FIXME:
    # Implement like this: compile_eval_arg
    # save the register, and loop over the "when"'s.
    # Compile each of the "when"'s as "if"'s where the value
    # is loaded from the stack and compared with the value
    # (or values) in the when clause

    @e.comment("compiling case expression")
    compare_exp = args.first

    @e.comment("compare_exp: #{compare_exp}")

    xrest = args.rest
    exprs = xrest[0]
    if xrest[1]
      exprs << xrest[1]
    end

    exprs = compile_whens(compare_exp, exprs)
    compile_eval_arg(scope, exprs)

    return Value.new([:subexpr])
  end

  def compile_stackframe(scope)
    @e.comment("Stack frame")
    Value.new([:reg,:ebp])
  end

  def compile_stackpointer(scope)
    @e.comment("Stack pointer")
    Value.new([:reg,:esp])
  end

  # Get address of a label
  # Similar to how Proc stores function addresses
  # Used for exception handling to save rescue handler address
  def compile_addr(scope, label)
    @e.comment("Get address of label #{label}")
    @e.movl("$#{label}", :eax)
    Value.new([:reg, :eax])
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
    @e.movl("-4(%ebp)",:ebx) # Restoring numargs from outside scope
    @e.popl(:eax)
    @e.leave
    @e.ret
    @e.evict_all
    return Value.new([:subexpr])
  end

  # Stack unwinding for exceptions (like preturn but for exception handlers)
  # Takes a handler object with saved_ebp, saved_esp, and handler_addr fields
  def compile_unwind(scope, handler_expr)
    @e.comment("raise - unwind to exception handler")

    # Evaluate handler expression to get the handler object
    handler = compile_eval_arg(scope, handler_expr)

    # Load handler fields
    @e.pushl(handler)
    @e.load_indirect(@e.sp, :ecx)
    @e.movl("4(%ecx)", :eax)   # Load saved_ebp (offset 1)
    @e.movl("8(%ecx)", :edx)   # Load saved_esp (offset 2)
    @e.movl("12(%ecx)", :esi)  # Load handler_addr (offset 3)
    @e.popl(:ecx)

    # Restore %ebp AND %esp to the saved state
    # This unwinds all intermediate stack frames
    @e.movl(:eax, :ebp)        # Set ebp to saved_ebp
    @e.movl(:edx, :esp)        # Set esp to saved_esp
    # Adjust ESP: saved_esp was captured during save_stack_state call when ESP
    # was adjusted for call overhead. We need to restore to the let() block base.
    # The save_stack_state call used 36 bytes (9 slots * 4 bytes)
    @e.addl(36, :esp)          # Restore to let() block base
    # Note: Don't restore %ebx here - let function epilogue handle it

    # Jump to handler
    @e.emit(:jmp, "*%esi")

    @e.evict_all
    return Value.new([:subexpr])
  end

  # Compiles and evaluates a given argument within a given scope.
  def compile_eval_arg(scope, arg)
    if arg.respond_to?(:position) && arg.position != nil
      pos = arg.position.inspect
      if pos != @lastpos
        if arg[0] != :defm
          @e.lineno(arg.position)
        end
        # trace(arg.position,arg)
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

    if atype == :addr || atype == :cvar
      scope.add_constant(aparam)
      prefix = scope.name
      aparam = prefix + "__" + aparam.to_s if !prefix.empty?
      @global_constants << aparam
    elsif atype == :ivar
      # FIXME:  The register allocation here
      # probably ought to happen in #save_to_instance_var
      @e.popl(source) if source.is_a?(Symbol)
      @e.pushl(source)
      ret = compile_eval_arg(scope, :self)
      @e.with_register do |reg|
        @e.popl(reg)
        @e.save_to_instance_var(reg, ret, aparam)
      end
      # FIXME: Need to check for "special" ivars
      return Value.new([:subexpr], :object)
    end

    # FIXME: Otherwise, "source" register may already have been reused
    if source.is_a?(Symbol)
      @e.popl(:eax)
      source = :eax
    end

    r = @e.save(atype, source, aparam)

    if !r
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
    source = nil
    exp.each do |e|
      source=compile_eval_arg(scope, e)
      @e.save_result(source)
    end

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
  # Parser returns: [:block, args, exps, rescue_clause, ensure_body]
  # For begin blocks: args=[], exps=body, rescue_clause=[:rescue, ...] or nil, ensure_body=... or nil
  def compile_block(scope, args, exps, rescue_clause = nil, ensure_body = nil)
    if rescue_clause || ensure_body
      compile_begin_rescue(scope, exps, rescue_clause, ensure_body)
    else
      compile_do(scope, *exps)
    end
  end

  # Compile begin...rescue...else...ensure...end block
  # rescue_clause = [:rescue, exception_class, var_name, body] or
  #                 [:rescue, exception_class, var_name, body, else_body]
  # ensure_body = expressions to run in all cases (nil if not present)
  def compile_begin_rescue(scope, exps, rescue_clause, ensure_body = nil)
    # Handle ensure-only blocks (no rescue)
    if !rescue_clause && ensure_body
      compile_do(scope, *exps)
      compile_do(scope, *ensure_body)
      return Value.new([:subexpr])
    end

    rescue_label = @e.get_local    # Label for rescue handler
    after_label = @e.get_local     # Label after rescue

    rescue_class = rescue_clause[1]
    rescue_var = rescue_clause[2]
    rescue_body = rescue_clause[3]
    else_body = rescue_clause[4]   # Optional else clause (nil if not present)

    # Generate code that:
    # 1. Pushes handler onto exception stack
    # 2. Saves stack state (ebp, esp, rescue_label address)
    # 3. Executes try block
    # 4. On normal completion: pops handler
    # 5. On exception: jumps to rescue_label (via ExceptionRuntime.raise)

    # Handle nil rescue_class - convert Ruby nil to :nil symbol which references global nil object
    # If we pass nil directly, get_arg treats it as an empty string constant (bug!)
    rescue_class_arg = rescue_class.nil? ? :nil : rescue_class

    # Build variable list for let() - include rescue_var if specified
    let_vars = [:__handler, :__exc]
    let_vars << rescue_var if rescue_var

    # Use let() to create local variables for handler, exception, and optional rescue var
    let(scope, *let_vars) do |lscope|
      # Push handler
      compile_eval_arg(lscope,
        [:assign, :__handler,
          [:callm, :$__exception_runtime, :push_handler, [rescue_class_arg]]])

      # Save stack state with CALLER's stackframe, stack pointer, and address of rescue label
      # The :stackframe and :stackpointer must be evaluated here, not inside save_stack_state
      compile_eval_arg(lscope,
        [:callm, :__handler, :save_stack_state, [[:stackframe], [:stackpointer], [:addr, rescue_label]]])

      # Compile try block
      compile_do(lscope, *exps)

      # Normal completion - pop handler
      compile_eval_arg(lscope, [:callm, :$__exception_runtime, :pop_handler])

      # Execute else clause if present (only runs when NO exception was raised)
      compile_do(lscope, *else_body) if else_body

      # Execute ensure clause if present (always runs on normal completion)
      compile_do(lscope, *ensure_body) if ensure_body

      @e.jmp(after_label)

      # Rescue handler label (jumped to by compile_unwind via :unwind primitive)
      @e.label(rescue_label)

      # Get exception from ExceptionRuntime singleton
      compile_eval_arg(lscope,
        [:assign, :__exc, [:callm, :$__exception_runtime, :current_exception]])

      # Bind to rescue variable if specified
      if rescue_var
        compile_assign(lscope, rescue_var, :__exc)
      end

      # Compile rescue body
      compile_do(lscope, *rescue_body) if rescue_body

      # Clear exception from singleton
      compile_eval_arg(lscope, [:callm, :$__exception_runtime, :clear])

      # Execute ensure clause if present (always runs even after rescue)
      compile_do(lscope, *ensure_body) if ensure_body

      # Jump to after label (rescue completed normally)
      @e.jmp(after_label)

      # IMPORTANT: after_label must be INSIDE the let() block so stack gets restored
      @e.label(after_label)
    end

    Value.new([:subexpr])
  end

  # Compile a literal Array initalization
  #
  # FIXME: An alternative is another "transform" step
  #
  def compile_array(scope, *initializers)
    compile_eval_arg(scope,
                      [:callm, :Array, :[], initializers]
                      )
    return Value.new([:subexpr], :object)
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
      if index.is_a?(Numeric)
        if index != 0
          @e.addl(index*4, reg)
        end
      else
        @e.pushl(reg)
        source = compile_eval_arg(scope, index)
        @e.save_result(source)
        @e.sall(2, @e.result_value)
        @e.popl(reg)
        @e.addl(@e.result_value, reg)
      end
    end
    return Value.new([:indirect, r], lookup_type(arr,index))
  end



  def let(scope,*varlist, &block)
    vars = Hash[*(varlist.zip(1..varlist.size)).flatten]
    lscope =LocalVarScope.new(vars, scope)
    if varlist.size > 0
      @e.evict_regs_for(varlist)
      # FIXME: I'm not actually sure why we need to add 1 here.
      # FIXME: @bug workaround for @e.with_local(vars.size+1) getting
      # turned into (callm @e with_local(callm (calm vars size) + 1))
      # (probable parser bug that leaves argument without parentheses
      # when single argument given
      s = vars.size + 2
      # FIXME: @bug: calling "with_local" does not work here, so trying
      # to avoid with "with_stack" (and adding 1 extra to var.size above.
      # Original line: @e.with_local(vars.size+1) do
      @e.with_stack(s) do
        block.call(lscope)
      end
      @e.evict_regs_for(varlist)
    else
      yield(lscope)
    end
  end


  # Compiles a let expression.
  # Takes the current scope, a list of variablenames as well as a list of arguments.
  def compile_let(scope, varlist, *args)
    # Filter out non-symbols from varlist - only actual variable names can be bound
    # Non-symbol expressions (like [:index, ...]) should only appear in assignments
    symbols_only = varlist.select {|v| v.is_a?(Symbol) }

    if varlist.size != symbols_only.size
      # Some elements were filtered - compile as a plain :do if no symbols remain
      return compile_do(scope, *args) if symbols_only.empty?
    end

    let(scope, *symbols_only) do |ls|
      compile_do(ls, *args)
    end
    return Value.new([:subexpr])
  end

  # Put at the start of a required file, to allow any special processing
  # before/after
  def compile_required(scope,exp)
    @e.include(exp.position.filename) do
      v = scope.get_arg(:__FILE__)
      if v[0] == :global
        compile_eval_arg(scope,[:assign, :__FILE__, [:sexp, [:__get_string,exp.position.filename]]])
      end
      ret = compile_exp(scope,exp)
      # FIXME: This of course doesn't do what it is intended
      # - it needs to reset filename back to its previous value.
      if v[0] == :global
        compile_eval_arg(scope,[:assign, :__FILE__, [:sexp, [:call, :__get_string,exp.position.filename]]])
      end
      ret
    end
  end

  # General method for compiling expressions.
  # Calls the specialized compile methods depending of the
  # expression to be compiled (e.g. compile_if, compile_call, compile_let etc.).
  def compile_exp(scope, exp)
    return Value.new([:subexpr]) if !exp || exp.size == 0

    # FIXME:
    # rescue is unsupported in:
    # pos = exp.position rescue nil
    #
    pos = nil
    if exp.respond_to?(:position)
      pos = exp.position
    end

    if pos && exp[0] != :defm
      @e.lineno(pos) if pos
    end
    #trace(pos,exp)

    # check if exp is within predefined keywords list

    ## FIXME: Attempt at fixing segfault
    cmd = nil
    r = nil
    exp
    if(@@keywords.include?(exp[0]))
      # FIXME: This variation segfaults
      return self.send("compile_#{exp[0].to_s}", scope, *exp.rest)
      #exp
      #cmd = "compile_#{exp[0].to_s}"
      #if cmd == "compile_defm"
        # FIXME: Uncommenting this causes crash to move elsewhere.
        #STDERR.puts scope.object_id
      #  r = exp.rest
      #  return self.compile_defm(scope, *r)
      #end
      #return self.send(cmd, scope, *exp.rest)
    elsif @@oper_methods.member?(exp[0])
      return compile_callm(scope, exp[1], exp[0], exp[2..-1])
    else
      return compile_call(scope, exp[1], exp[2],exp[3], pos) if (exp[0] == :call)
      return compile_callm(scope, exp[1], exp[2], exp[3], exp[4]) if (exp[0] == :callm)
      return compile_call(scope, exp[0], exp.rest, nil, pos) if (exp.is_a? Array)
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
      compile_eval_arg(@global_scope, [:sexp, [:assign, :__stack_top, [:stackframe]]])

      # Initialize all global variables (starting with $) to nil
      @global_scope.globals.keys.each do |g|
        if g.to_s[0] == ?$
          compile_eval_arg(@global_scope, [:assign, g, :nil])
        end
      end

      compile_eval_arg(@global_scope, exp)
      compile_eval_arg(@global_scope, [:sexp,[:exit, 0]])
      nil
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
      # Don't skip - we need to find nested :defm nodes (e.g., methods defined in eigenclasses inside methods)
    end

    exp.depth_first(:alias) do |aliasnode|
      @vtableoffsets.alloc_offset(aliasnode[1])  # Allocate offset for new_name
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
    @e.label("__vtable_thunks_helper")
      @e.popl(:ebx) # numargs
      @e.movl("4(%esp)",:esi)  # self

      # Making space for the symbolx for the method.
      @e.movl("(%esp)", :ecx)  # Return address
      @e.pushl(:ecx)

      # Self into new position
      @e.movl(:esi, "4(%esp)")

      # Block into new position
      @e.movl("12(%esp)",:ecx)
      @e.movl(:ecx, "8(%esp)")

      # Symbol as first argument
      @e.movl(:eax,"12(%esp)")

      # Adjust argument count
      @e.addl(1,:ebx)

      load_class(@global_scope)
      @e.jmp("*__voff__method_missing(%eax)")

    @e.label("__vtable_thunks_start")
    @vtableoffsets.vtable.each do |name,_|
      @e.label("__vtable_missing_thunk_#{clean_method_name(name)}")
      @e.pushl(:ebx)
      # FIXME: Call get_symbol for all of these during init?
      # Currently only ones matching names statically mentioned
      # in the source get optimized.
      arg = nil
      if @symbols.member?(name.to_s)
        arg = symbol_name(name.to_s)
      else
        arg = ":#{name.to_s}".to_sym
      end
      
      @e.save_result(compile_eval_arg(@global_scope, arg))
      @e.jmp("__vtable_thunks_helper")
    end
    @e.label("__vtable_thunks_end")

    @e.label("__base_vtable")
    # For ease of implementation of __new_class_object we
    # pad this with the number of class ivar slots so that the
    # vtable layout is identical as for a normal class
    ClassScope::CLASS_IVAR_NUM.times { @e.long(0) }

    # FIXME: the e[1] here appears to be incorrectly rewritten.
    @vtableoffsets.vtable.to_a.sort_by {|e| e[1] }.each do |e|
      @e.long("__vtable_missing_thunk_#{clean_method_name(e[0])}")
    end
  end

  def output_vtable_names
    @e.emit(".equ", "__vtable_size, "+@vtableoffsets.max.to_s)
    @e.label("__vtable_names")
    ClassScope::CLASS_IVAR_NUM.times { @e.long(0) }
    @vtableoffsets.vtable.to_a.sort_by {|e| e[1] }.each do |e|
      sc = strconst(e[0].to_s)
      @e.emit(".long", sc.last)
    end

    @e.comment("")
  end

  # Output function to initialize global variables to nil if still uninitialized (0)
  def output_global_init
    @e.export("__init_globals", "function")
    @e.label("__init_globals")
    @e.emit(".LFBB__init_globals:")

    # Check each variable in global scope - if it starts with $ and is still 0, initialize to nil
    @global_scope.globals.keys.each do |g|
      if g.to_s[0] == ?$
        name = g.to_s[1..-1]  # Strip $ prefix
        skip_label = @e.get_local

        # Check if still 0 (uninitialized)
        @e.movl(name, :eax)
        @e.testl(:eax, :eax)
        @e.jnz(skip_label)  # If not zero, skip

        # Initialize to nil
        @e.movl("nil", :eax)
        @e.movl(:eax, name)

        @e.label(skip_label)
      end
    end

    @e.ret
  end

  # Starts the actual compile process.
  def compile exp
    alloc_vtable_offsets(exp)
    compile_main(exp)
    # after the main function, we ouput all functions and constants
    # used and defined so far.
    output_global_init
    output_functions
    output_vtable_thunks
    output_vtable_names
    output_constants
    @e.flush
  end

  def compile_splat(scope, expr)
    # In break/return/next context, *array simply evaluates to the array itself
    # Example: break *[1, 2] returns [1, 2]
    # Evaluate the expression and return it as a subexpression (result in %eax)
    compile_eval_arg(scope, expr)
    return Value.new([:subexpr], :object)
  end
end
