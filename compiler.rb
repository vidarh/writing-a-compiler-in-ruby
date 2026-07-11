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
                   :hash, :return,:sexp, :module, :rescue, :rescues, :raise, :incr, :decr, :block,
                   :required, :add, :sub, :mul, :div, :shl, :sar, :sarl, :sall, :eq, :ne,
                   :lt, :le, :gt, :ge,:saveregs, :and, :or,
                   :preturn, :stackframe, :caller_stackframe, :stackpointer, :deref, :include, :addr, :lvaraddr,
                   :protected, :array, :splat, :mod, :or_assign, :and_assign, :break, :next, :alias, :undef,
                   :mul_assign, :div_assign, :mod_assign, :pow_assign,
                   :and_bitwise_assign, :or_bitwise_assign, :xor_assign,
                   :lshift_assign, :rshift_assign,
                   :__compiler_internal, # See `compile_pragma.rb`
                   :__inline, # See `inline.rb`
                   :bitand, :bitor, :bitxor, # Bitwise operators
                   :mulfull, # Widening multiply - returns both low and high words
                  :div64, # 64-bit division - divides EDX:EAX by operand
                  :unwind, # Exception stack unwinding
                  :pattern, # Pattern matching (Ruby 3.0+)
                  :as_pattern, # AS patterns in pattern matching (Ruby 3.0+)
                  :float, # Float literal [:float, "<decimal-string>"] -> see compile_float
                  # x87 double primitives used by lib/core/float.rb. Each takes THREE Float-object
                  # pointers (a b result); the double lives at offset 4. `(fadd a b r)` does `r = a + b`.
                  :fadd, :fsub, :fmul, :fdiv,
                  # x87 <-> integer conversions. `(ftoi f)` truncates the double at 4(f) toward zero and
                  # returns a TAGGED fixnum. `(fint i r)` writes (double)i into the Float pointed to by r.
                  :ftoi, :fint,
                  # x87 ordered comparisons. Each returns a raw 0/1 flag (like the integer :lt/:eq
                  # primitives) for use inside `(if ...)`. NaN is unordered: flt/fgt/feq all yield 0.
                  :flt, :fgt, :feq,
                  # x87 unary ops: `(fneg f r)` writes -*f into r (fchs); `(fabs f r)` writes |*f| (fabs).
                  :fneg, :fabs,
                  # `(fstresult r)` stores the current FPU st0 into the Float object r (double at offset 4)
                  # and pops. Used to capture the double RETURN (in st0) of a directly-called libc function
                  # e.g. `(do (sqrt lo hi) (fstresult r))` or `(do (strtod s 0) (fstresult r))`.
                  :fstresult,
                  # pack/unpack float conversions via x87. `(fstored f buf)` writes f's 8 double bytes into
                  # buf; `(fstores f buf)` writes the 4-byte single (fstps). `(floadd buf r)` / `(floads buf r)`
                  # load 8/4 bytes from buf into the Float r (flds widens single->double). buf is a raw ptr.
                  :fstored, :fstores, :floadd, :floads
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
    @clean_method_cache = {}
    @compile_names = {}
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
    # Captured-variable env slots hold Ruby OBJECTS (so conditions on them need full nil/false
    # truthiness); slot 0 (stack frame) and slot 1 (parent env link) are raw words. The base may
    # be :__env__ itself or a parent-hop chain [:index, [...], 1] bottoming out at :__env__
    # (nested-env wrappers; see __env_hops in transform.rb). Without the unwrap, a captured
    # variable read from a nested block was typed raw, and `captured && ...` took the truthy
    # branch on a FALSE object (nonzero pointer) -- compile_callm's own do_load_super guard then
    # called false.to_sym when the compiler compiled itself.
    v = var
    while v.is_a?(Array) && v[0] == :index && v[2] == 1
      v = v[1]
    end
    if v == :__env__ && index != 0 && index != 1
      :object
    else
      nil
    end
  end

  # Emit a Float object holding the double named by `decimal_str` (e.g. "1.5", "1.5e10", "inf", "nan").
  # The value goes into rodata as `.double <decimal_str>` (the ASSEMBLER converts decimal->IEEE, so no
  # compile-time float math is needed), then storedouble (x87 fldl/fstpl) copies the 8 bytes into the new
  # object at offset 4 (after the vtable pointer). Shared by the [:float, str] literal path and any native
  # Ruby Float that reaches get_arg MRI-hosted.
  def emit_float_const(scope, decimal_str)
    label = ".float_#{@float_constants.length}"
    @float_constants[label] = decimal_str
    ptr = compile_exp(scope, [:callm, :Float, :new])
    @e.storedouble(:eax, 4, label)
    ptr
  end

  # [:float, "<decimal-string>"] literal node (produced by the tokeniser; see tokens.rb Number.expect).
  def compile_float(scope, decimal_str)
    emit_float_const(scope, decimal_str)
  end

  # x87 double binary op: `result = a <op> b`, where a/b/result are Float-object pointers whose double
  # lives at offset 4. Each operand is evaluated then immediately consumed (fldl/f<op>l/fstpl), so no
  # pointer is held across another evaluation. `fldl a; f<op>l b; fstpl result` is FPU-stack-balanced.
  def compile_fbinop(scope, mnemonic, a, b, result)
    @e.save_result(compile_eval_arg(scope, a))       # eax = ptr a
    @e.fldl("4(%eax)")             # st0 = *a  (a now consumed onto the FPU stack)
    @e.save_result(compile_eval_arg(scope, b))       # eax = ptr b
    @e.emit(mnemonic, "4(%eax)")   # st0 = st0 <op> *b
    @e.save_result(compile_eval_arg(scope, result))  # eax = ptr result
    @e.fstpl("4(%eax)")            # *result = st0
    Value.new([:subexpr])
  end

  def compile_fadd(scope, a, b, result); compile_fbinop(scope, :faddl, a, b, result); end
  def compile_fsub(scope, a, b, result); compile_fbinop(scope, :fsubl, a, b, result); end
  def compile_fmul(scope, a, b, result); compile_fbinop(scope, :fmull, a, b, result); end
  def compile_fdiv(scope, a, b, result); compile_fbinop(scope, :fdivl, a, b, result); end

  # `(ftoi f)` -> tagged fixnum. Truncates the double at 4(f) toward zero (MRI Float#to_i semantics).
  # x87 fistpl uses the current rounding mode, so we temporarily set RC=truncate (control-word bits
  # 10-11 = 11, i.e. |0xC00) around the store and restore the caller's mode afterwards. 8 scratch bytes:
  # [esp]=saved cw, [esp+2]=truncate cw, [esp+4]=the 32-bit int result.
  def compile_ftoi(scope, a)
    @e.save_result(compile_eval_arg(scope, a))  # eax = ptr to the Float
    @e.fldl("4(%eax)")                 # st0 = *self
    @e.subl(8, :esp)
    @e.emit(:fnstcw, "(%esp)")         # save current control word
    @e.emit(:movw, "(%esp)", "%ax")
    @e.emit(:orw, "$3072", "%ax")      # 0xC00 -> RC = round-toward-zero (truncate)
    @e.emit(:movw, "%ax", "2(%esp)")
    @e.emit(:fldcw, "2(%esp)")         # activate truncation
    @e.emit(:fistpl, "4(%esp)")        # store truncated int, pop st0
    @e.emit(:fldcw, "(%esp)")          # restore caller's rounding mode
    @e.movl("4(%esp)", :eax)           # eax = raw signed int
    @e.addl(8, :esp)
    @e.leal("1(%eax,%eax,1)", :eax)    # tag as fixnum: eax*2+1
    Value.new([:reg, :eax])
  end

  # `(fint i r)` writes (double)i into the Float pointed to by r (double at offset 4). `i` is a tagged
  # fixnum, so we arithmetic-shift it back to a raw int, spill it to the stack, and fildl it onto st0.
  def compile_fint(scope, a, result)
    @e.save_result(compile_eval_arg(scope, a))       # eax = tagged fixnum
    @e.sarl(1, :eax)                   # untag fixnum -> raw int
    @e.subl(4, :esp)
    @e.movl(:eax, "(%esp)")
    @e.emit(:fildl, "(%esp)")          # st0 = (double) raw int
    @e.addl(4, :esp)
    @e.save_result(compile_eval_arg(scope, result))  # eax = ptr result
    @e.fstpl("4(%eax)")                # *result = st0
    Value.new([:subexpr])
  end

  # Load *b then *a so the FPU stack is st0=*a, st1=*b, then `fucompp` compares st0:st1 and pops both.
  # `fucompp` (unordered) does NOT fault on NaN. After `fnstsw %ax; sahf`: CF=C0 (a<b OR unordered),
  # ZF=C3 (a==b OR unordered), PF=C2 (set iff unordered). Callers mask PF to exclude the NaN case.
  def compile_fcmp_setup(scope, a, b)
    @e.save_result(compile_eval_arg(scope, b))
    @e.fldl("4(%eax)")                 # st0 = *b
    @e.save_result(compile_eval_arg(scope, a))
    @e.fldl("4(%eax)")                 # st0 = *a, st1 = *b
    @e.emit(:fucompp)
    @e.fnstsw_ax
    @e.emit(:sahf)
  end

  # a < b : CF=1 but NOT unordered (PF=0).
  def compile_flt(scope, a, b)
    compile_fcmp_setup(scope, a, b)
    @e.emit(:setb, "%al")
    @e.emit(:setnp, "%cl")
    @e.emit(:andb, "%cl", "%al")
    @e.movzbl(:al, :eax)
    Value.new([:reg, :eax])
  end

  # a > b : CF=0 AND ZF=0 (`seta`). Unordered has CF=1, so `seta` already yields 0 there.
  def compile_fgt(scope, a, b)
    compile_fcmp_setup(scope, a, b)
    @e.emit(:seta, "%al")
    @e.movzbl(:al, :eax)
    Value.new([:reg, :eax])
  end

  # a == b : ZF=1 but NOT unordered (PF=0), so NaN == NaN is false.
  def compile_feq(scope, a, b)
    compile_fcmp_setup(scope, a, b)
    @e.emit(:sete, "%al")
    @e.emit(:setnp, "%cl")
    @e.emit(:andb, "%cl", "%al")
    @e.movzbl(:al, :eax)
    Value.new([:reg, :eax])
  end

  # x87 unary op: result = <insn>(*a), where insn is a no-operand FPU instruction (fchs / fabs).
  def compile_funop(scope, insn, a, result)
    @e.save_result(compile_eval_arg(scope, a))
    @e.fldl("4(%eax)")                 # st0 = *a
    @e.emit(insn)                      # st0 = <insn>(st0)
    @e.save_result(compile_eval_arg(scope, result))
    @e.fstpl("4(%eax)")                # *result = st0
    Value.new([:subexpr])
  end

  def compile_fneg(scope, a, result); compile_funop(scope, :fchs, a, result); end
  def compile_fabs(scope, a, result); compile_funop(scope, :fabs, a, result); end

  # Capture the double currently in FPU st0 (e.g. the return value of a directly-called libc function
  # such as sqrt/strtod, which the cdecl/x87 ABI returns in st0) into the Float object `result`.
  def compile_fstresult(scope, result)
    @e.save_result(compile_eval_arg(scope, result))  # eax = ptr to the result Float
    @e.fstpl("4(%eax)")                               # *result = st0 (and pop)
    Value.new([:subexpr])
  end

  # pack: store f's double (fstored, 8 bytes) or narrowed single (fstores, 4 bytes) into the raw buffer buf.
  def compile_fstored(scope, a, buf)
    @e.save_result(compile_eval_arg(scope, a))
    @e.fldl("4(%eax)")
    @e.save_result(compile_eval_arg(scope, buf))
    @e.fstpl("(%eax)")
    Value.new([:subexpr])
  end

  def compile_fstores(scope, a, buf)
    @e.save_result(compile_eval_arg(scope, a))
    @e.fldl("4(%eax)")
    @e.save_result(compile_eval_arg(scope, buf))
    @e.emit(:fstps, "(%eax)")
    Value.new([:subexpr])
  end

  # unpack: load 8 bytes (floadd) or a 4-byte single widened to double (floads) from buf into Float r.
  def compile_floadd(scope, buf, result)
    @e.save_result(compile_eval_arg(scope, buf))
    @e.fldl("(%eax)")
    @e.save_result(compile_eval_arg(scope, result))
    @e.fstpl("4(%eax)")
    Value.new([:subexpr])
  end

  def compile_floads(scope, buf, result)
    @e.save_result(compile_eval_arg(scope, buf))
    @e.emit(:flds, "(%eax)")
    @e.save_result(compile_eval_arg(scope, result))
    @e.fstpl("4(%eax)")
    Value.new([:subexpr])
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

    # A native Ruby Float can still reach here MRI-hosted (e.g. a constant-folded value); emit it via
    # its own decimal string so the rodata `.double` is identical to the literal path. Self-hosted no
    # Ruby Float is ever produced (the compiler has no float literals/arithmetic of its own).
    return emit_float_const(scope, a.to_s) if a.is_a?(Float)

    if a == :"block_given?"
      return compile_exp(scope,
                         [:if,
                          [:ne, :__closure__, 0],
                          :true, :false])
    end

    # (bare `caller` is handled by Kernel#caller now, not special-cased here -- see lib/core/kernel.rb)
    arg = nil
    if (a.is_a?(Symbol))
      name = a.to_s
      return intern(scope,name[1..-1]) if name[0] == ?:

      arg = scope.get_arg(a, save)

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

  # Helper to convert a constant name string to AST form for runtime string lookup
  # Returns [[:sexp, [:call, :__get_string, label.to_sym]]] (wrapped in array for call args)
  # Matches the pattern used in transform.rb rewrite_strconst line 121 + 127
  def const_name_to_string_ast(name_str)
    lab = @string_constants[name_str] || (@string_constants[name_str] = @e.get_local)
    return [[:sexp, [:call, :__get_string, lab.to_sym]]]
  end

  # True when the decimal float-literal string is so large it overflows an IEEE double (-> Infinity in
  # MRI, and un-assemblable by gas). Must be self-hostable: plain string ops only, no String#to_f (a
  # stub in the self-hosted compiler) and no regex. Estimates the base-10 order of magnitude from the
  # integer-part length plus any explicit exponent; a double tops out just under 10**309.
  def __float_literal_overflows?(str)
    s = str
    s = s[1..-1] if s[0..0] == "-"
    mant = s
    exp = 0
    ei = s.index("e")
    ei = s.index("E") if ei.nil?
    if ei
      exp = s[(ei + 1)..-1].to_i
      mant = s[0...ei]
    end
    di = mant.index(".")
    intpart = di ? mant[0...di] : mant
    order = exp + intpart.length - 1
    order > 308
  end

  # Outputs all constants used within the code generated so far.
  # Outputs them as string and global constants, respectively.
  def output_constants
    @e.rodata do
      @string_constants.each { |c, l| @e.string(l, c) }
      @float_constants.each do |label, value|
        @e.emit(label + ":")
        # gas cannot assemble a .double that overflows the IEEE double range (e.g. `1e1020` ->
        # "Error: cannot create floating-point number"). MRI treats such a literal as +/-Infinity, so
        # emit the Infinity bit pattern directly for a clearly-overflowing literal.
        if __float_literal_overflows?(value)
          @e.emit(".quad", (value[0..0] == "-") ? "0xfff0000000000000" : "0x7ff0000000000000")
        else
          @e.emit(".double", value)
        end
      end
    end

    # FIXME: Temporary workaround to add bss entries for "missing" globals
    # Global names are already assembly-safe (aliases applied, $ prefix stripped by globalscope.rb)
    vars = (@global_constants.to_a + @global_scope.globals.keys).collect{|s| s.to_s}.sort.uniq - ["__roots_start","__roots_end"]
    @e.bss    do
      @e.label("__roots_start")
      vars.each { |c|    @e.bsslong(c) }
      @e.label("__roots_end")
    end
  end


  # Need to clean up the name to be able to use it in the assembler.
  # Strictly speaking we don't *need* to use a sensible name at all,
  # but it makes me a lot happier when debugging the asm.
  # Operator-char -> mangled-name lookup. A constant (was a Hash literal rebuilt on every call, i.e. per
  # compiled method -- 15 entries + ~30 String literals each time).
  CLEAN_METHOD_DICT = {
    "?" => "__Q",     "!"  => "__X",
    "[]" => "__NDX",  "==" => "__eq",
    ">=" => "__ge",   "<=" => "__le",
    "<"  => "__lt",   ">"  => "__gt",
    "/"  => "__div",  "*"  => "__mul",
    "+"  => "__plus", "-"  => "__minus",
    "-@" => "__uminus", "+@" => "__uplus",
    "~"  => "__tilde"}.freeze

  def clean_method_name(name)
    # The same method names are cleaned on every call site that uses them (a program calls to_s/push/<<...
    # thousands of times), and the char-scan below rebuilds an `out` String each time. Memoize by name --
    # the cleaned label is a pure function of the name. Both hosts. (Explicit []=, not ||=: the op-assign
    # index form `@cache[name] ||= ...` returns nil self-hosted -> caller does `nil + ...`.)
    out = @clean_method_cache[name]
    if !out
      out = build_clean_method_name(name)
      @clean_method_cache[name] = out
    end
    out
  end

  def build_clean_method_name(name)
    dict = CLEAN_METHOD_DICT

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
  # Flatten a deref parent chain to its qualified name ("Outer::Inner").
  # Returns nil when any component is not a plain symbol (dynamic parent).
  def __deref_parent_name(left)
    return left.to_s if left.is_a?(Symbol)
    if left.is_a?(Array) && left[0] == :deref
      parts = []
      n = left
      while n.is_a?(Array) && n[0] == :deref
        if n.length == 3
          return nil if !n[2].is_a?(Symbol)
          parts.unshift(n[2].to_s)
        end
        n = n[1]
      end
      return nil if !n.is_a?(Symbol)
      parts.unshift(n.to_s)
      return parts.join("::")
    end
    nil
  end

  def compile_deref(scope, left = nil, right = nil)
    # Handle malformed :deref node (no children)
    # This can occur when transform.rb incorrectly adds [:deref] to a :let variables list
    if left.nil?
      error("Malformed :deref node with no children - likely a transform bug: right=#{right.inspect}", scope)
    end

    # Prefix form: ::Constant (global scope lookup)
    # When :: is used as prefix, left is the constant name and right is nil
    if right.nil?
      # ::Constant means look up Constant in global scope
      constant_name = left
      return get_arg(@global_scope, constant_name)
    end

    # Special case: self::Constant is a runtime lookup that can't be resolved statically
    # This commonly appears in defined?(self::Constant)
    # Generate runtime lookup: __const_get_on(self, "ConstantName")
    if left == :self
      res = compile_eval_arg(scope, [:call, :__const_get_on, [:self] + const_name_to_string_ast(right.to_s)])
      @e.save_result(res)
      return Value.new([:subexpr])
    end

    # If left is an expression (like [:deref, :Foo]), we need to resolve it to get the scope
    # This handles ::Foo::Bar where left is [:deref, :Foo] (prefix form)
    is_global_prefix = false
    if left.is_a?(Array) && left[0] == :deref
      # For ::Foo::Bar, left is [:deref, :Foo] and right is :Bar
      # We need to resolve ::Foo to get its scope, then look up Bar in that scope

      # Extract the constant name from the deref expression
      # [:deref, :Foo] means ::Foo (prefix form)
      # [:deref, :A, :B] means A::B (infix form)
      if left.length == 2
        # Prefix form: [:deref, :Foo] means ::Foo
        # This is a global scope lookup
        is_global_prefix = true
        constant_name = left[1]
        # Try multiple lookup strategies:
        # 1. Direct lookup in @classes with simple name
        # 2. Lookup in @classes with Object__ prefix (top-level classes)
        # 3. Lookup in global scope
        cscope = @classes[constant_name]
        cscope ||= @classes["Object__#{constant_name}".to_sym]
        cscope ||= @global_scope.find_constant(constant_name)
      elsif left.length == 3
        # Infix form: [:deref, :A, :B] means A::B
        # Recursively resolve to get the scope
        parent_scope_name = left[1]
        child_constant_name = left[2]
        parent_scope = scope.find_constant(parent_scope_name)
        if parent_scope && parent_scope.is_a?(ModuleScope)
          cscope = parent_scope.find_constant(child_constant_name)
        end
      end

      # If we couldn't resolve the nested/complex deref, generate runtime lookup
      if !cscope && (left.is_a?(Array) && left[0] == :deref)
        res = compile_eval_arg(scope, [:call, :__const_get_on, [left] + const_name_to_string_ast(right.to_s)])
        @e.save_result(res)
        return Value.new([:subexpr])
      end
    else
      cscope = scope.find_constant(left)
    end


    if !cscope || !cscope.is_a?(ModuleScope)
      # Cannot resolve statically - generate runtime constant lookup
      # This commonly appears in defined?(Undefined::Constant) where the constant doesn't exist
      pname = __deref_parent_name(left)
      pname = left.to_s if pname.nil?
      args_array = const_name_to_string_ast(pname) + const_name_to_string_ast(right.to_s)
      res = compile_eval_arg(scope, [:call, :__const_get, args_array])
      @e.save_result(res)
      return Value.new([:subexpr])
    end

    # For global prefix lookups (::Foo::Bar), we need special handling because
    # constants may have Object__ prefix due to transform/compile phase discrepancies
    if is_global_prefix
      prefix = cscope.name
      if !prefix.empty?
        mangled_name = prefix + "__" + right.to_s
        # Workaround for discrepancy between transform-phase and compile-phase class scopes:
        # Top-level classes may be stored with Object__ prefix in transform but without it in compile.
        if !@global_constants.include?(mangled_name) && !@global_constants.include?(mangled_name.to_sym)
          if !prefix.include?("__")  # Only for non-nested classes
            alt_name = "Object__" + mangled_name
            if @global_constants.include?(alt_name) || @global_constants.include?(alt_name.to_sym)
              mangled_name = alt_name
            end
          end
        end
        # Use :global type to generate movl (dereference), not movl $ (address)
        return Value.new([:global, mangled_name], :object)
      end
    end

    ret = get_arg(cscope,right)
    # An unknown member under a statically-known parent falls all the way through the scope
    # chain to a BARE-name global lookup ([:runtime_const, right] -> __const_get_global(right)),
    # losing the parent qualification: `Struct::Useful` raised "uninitialized constant Useful"
    # even though Struct.new("Useful", ...) had registered "Struct::Useful" in the runtime
    # constant table. Emit the QUALIFIED runtime lookup instead.
    if ret.is_a?(Array) && ret[0] == :runtime_const
      # left may be a NESTED deref ([:deref, :Outer, :Inner]) -- flatten to the
      # qualified name; left.to_s would bake the raw AST into the key.
      pname = __deref_parent_name(left)
      pname = left.to_s if pname.nil?
      args_array = const_name_to_string_ast(pname) + const_name_to_string_ast(right.to_s)
      res = compile_eval_arg(scope, [:call, :__const_get, args_array])
      @e.save_result(res)
      return Value.new([:subexpr])
    end
    ret
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

  def compile_rescue(scope, rval, lval, else_body = nil)
    # Note: rescue is now handled via compile_begin_rescue in compile_block
    # This method is kept for backwards compatibility but shouldn't be called
    # The else_body parameter is accepted but ignored (handled in compile_block)
    compile_exp(scope,lval)
  end

  # Compile raise statement
  # Transforms raise into a call to Kernel#raise
  # - Bare raise: re-raises current exception ($!)
  # - raise(arg): calls raise with argument
  # - raise(exc, msg): calls raise with exception class and message
  def compile_raise(scope, *args)
    if args.empty?
      # Bare raise - re-raise current exception stored in $!
      return compile_callm(scope, :self, :raise, [:"$!"])
    else
      # raise with arguments - pass them through to Kernel#raise
      return compile_callm(scope, :self, :raise, args)
    end
  end

  def compile_decr(scope, left, right)
    compile_assign(scope, left, [:callm, left, :-, [right]])
  end

  def compile_incr(scope, left, right)
    compile_assign(scope, left, [:callm, left, :+, [right]])
  end

  def compile_mul_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :*, [right]])
  end

  def compile_div_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :/, [right]])
  end

  def compile_mod_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :%, [right]])
  end

  def compile_pow_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :**, [right]])
  end

  def compile_and_bitwise_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :&, [right]])
  end

  def compile_or_bitwise_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :|, [right]])
  end

  def compile_xor_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :^, [right]])
  end

  def compile_lshift_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :<<, [right]])
  end

  def compile_rshift_assign(scope, left, right)
    compile_assign(scope, left, [:callm, left, :>>, [right]])
  end

  def compile_and_assign(scope, left, right)
    # a &&= b is equivalent to: a && (a = b)
    # Only assigns if a is truthy
    compile_if(scope, left, [:assign, left, right])
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
    # Separate hash_splat elements from regular pairs
    splats = []
    pairs = []

    args.each do |elem|
      if elem.is_a?(Array) && elem[0] == :hash_splat
        splats << elem[1]
      elsif elem.is_a?(Array) && elem[0] == :pair
        pairs << elem[1]
        pairs << elem[2]
      else
        error("Literal Hash must contain key value pairs or hash splat only: elem=#{elem.inspect}",scope,args)
      end
    end

    # If no splats, use the simple Hash[] approach
    if splats.empty?
      return compile_callm(scope, :Hash, :[], pairs)
    end

    # Build a nested s-expression for merging splats and pairs.
    # Start from a fresh empty Hash and merge every splat into it. Ruby's `{**h}` / `foo(**h)` build a NEW
    # hash (they copy h, they do not alias it), so seeding with `Hash[]` is both correct and side-steps a
    # bug: a lone `**h` with no other entries used to leave result_expr as the bare splat operand (e.g. the
    # Symbol `:h`), which compile_exp then mis-compiled -- compile_exp reads exp[0] as a node tag, and for a
    # bare Symbol `:h[0]` is the character "h", so `{**h}` produced garbage. Routing through `Hash[].merge`
    # keeps the operand in callm-receiver position, where it resolves as a normal variable.
    result_expr = [:callm, :Hash, :[], []]

    # Merge each splat
    splats.each do |splat_expr|
      result_expr = [:callm, result_expr, :merge, [splat_expr]]
    end

    # If there are literal pairs, merge them too
    unless pairs.empty?
      literal_hash_expr = [:callm, :Hash, :[], pairs]
      result_expr = [:callm, result_expr, :merge, [literal_hash_expr]]
    end

    compile_exp(scope, result_expr)
  end

  # FIXME: Compiler @bug: This method was a self-recursive
  # lambda in `#compile_case`
  def compile_case_test(compare_exp, test_exprs)
    test_value = test_exprs
    xrest = nil
    if test_exprs.is_a?(Array)
      if test_exprs[0] == :comma
        test_value = test_exprs[1]
        xrest = test_exprs[2]  # Keep as-is, don't wrap in Array()
      end
    end
    # When compare_exp is nil (case with no condition), test for truthiness
    # Otherwise use === comparison
    if compare_exp.nil?
      cmp = test_value
    elsif test_value.is_a?(Array) && test_value[0] == :splat
      # `when *a`: match if ANY element of the splatted array === compare_exp. Emitting the plain
      # `(*a).===(x)` splats the array into the argument list of === (given N, expected 1). Delegate to
      # a runtime helper that coerces to an array and iterates.
      cmp = [:callm, test_value[1], :__when_splat_match, [compare_exp]]
    else
      cmp = [:callm, test_value, :===, [compare_exp]]
    end

    if xrest.nil?
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

    # Handle both :when and :in branches (pattern matching uses :in)
    if exp[0] == :when || exp[0] == :in
      test_values = exp[1]

      body = exp[2] # body to be executed, if compare_exp === test_value

      @e.comment(Emitter::COMMENTS && "test_value: #{test_values.inspect}")
      @e.comment(Emitter::COMMENTS && "body: #{body.inspect}")

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

    @e.comment(Emitter::COMMENTS && "compiling case expression")
    compare_exp = args.first

    @e.comment(Emitter::COMMENTS && "compare_exp: #{compare_exp}")

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
    @e.comment(Emitter::COMMENTS && "Stack frame")
    Value.new([:reg,:ebp])
  end

  # Returns the caller's stack frame pointer (saved %ebp on stack)
  # Used by Proc#call to capture the yielder's frame for break support
  def compile_caller_stackframe(scope)
    @e.comment(Emitter::COMMENTS && "Caller's stack frame")
    @e.movl("(%ebp)", :eax)
    Value.new([:reg, :eax])
  end

  def compile_stackpointer(scope)
    @e.comment(Emitter::COMMENTS && "Stack pointer")
    Value.new([:reg,:esp])
  end

  # Address of a local variable or argument slot: (lvaraddr name) -> &name (a raw %ebp-relative pointer).
  # Mirrors :argaddr but for any local/arg. Used to build a call-scoped struct (e.g. a block descriptor)
  # in the current frame and pass its address, avoiding a heap allocation. The pointer is valid only for
  # the current frame's lifetime -- fine for a value consumed within a call made from this frame.
  def compile_lvaraddr(scope, name)
    a = scope.get_arg(name)
    @e.comment(Emitter::COMMENTS && "lvaraddr #{name}")
    if a[0] == :arg
      @e.load(:argaddr, a[1])
    elsif a[0] == :lvar
      @e.load(:lvaraddr, a[1])
    else
      raise "lvaraddr: #{name.inspect} resolved to #{a.inspect}, not a local/arg"
    end
    Value.new([:reg, :eax])
  end

  # Get address of a label
  # Similar to how Proc stores function addresses
  # Used for exception handling to save rescue handler address
  def compile_addr(scope, label)
    @e.comment(Emitter::COMMENTS && "Get address of label #{label}")
    @e.movl("$#{label}", :eax)
    Value.new([:reg, :eax])
  end

  # "Special" return for `proc` and bare blocks
  # to exit past Proc#call.
  def compile_preturn(scope, arg = nil)
    @e.comment(Emitter::COMMENTS && "preturn")

    @e.save_result(compile_eval_arg(scope, arg)) if arg
    @e.pushl(:eax)

    # The target is the DEFINING METHOD's frame: slot 0 of the ROOT env. Under nested envs
    # (see process_scope_env's layout comment) the current __env__ may be a per-activation
    # wrapper; walk the parent links (slot 1; 0 terminates at the root) first, then read the
    # root's slot 0. `break` by contrast targets slot 0 of the CURRENT env (its defining
    # activation) in compile_break. Emitted directly (a sexp-let here mis-resolved __env__ as
    # a raw asm symbol in some scopes).
    ret = compile_eval_arg(scope, :__env__)
    @e.save_result(ret)
    l_walk = @e.get_local + "_pwalk"
    l_done = @e.get_local + "_pdone"
    @e.local(l_walk)
    @e.movl("4(%eax)", :edx)     # parent link (slot 1); 0 at the root
    @e.testl(:edx, :edx)
    @e.je(l_done)
    @e.movl(:edx, :eax)
    @e.jmp(l_walk)
    @e.local(l_done)
    @e.movl("(%eax)", :eax)      # root slot 0 = defining method's frame

    # Pre-scan (mirrors compile_break's): before jumping, verify the target frame is actually on the
    # current stack by walking the saved-%ebp chain from the current frame. A proc containing `return`
    # that is captured and called AFTER its defining method returned (`def m; Proc.new { return }; end;
    # m.call`) carries a dead frame pointer; jumping through it executed stack garbage and segfaulted.
    # If the chain is exhausted (saved %ebp of 0, or not strictly increasing) before the target is
    # found, raise LocalJumpError ("unexpected return") instead, matching MRI. The walk only reads the
    # saved-%ebp slots of live frames, so it cannot fault.
    l_scan  = @e.get_local + "_scan"
    l_found = @e.get_local + "_found"
    l_noret = @e.get_local + "_noret"
    @e.movl("(%ebp)", :edx)      # walker starts at the current frame's caller
    @e.local(l_scan)
    @e.cmpl(:eax, :edx)          # walker == target frame?
    @e.je(l_found)
    @e.movl("(%edx)", :ebx)      # next = saved %ebp (caller's frame)
    @e.cmpl(:edx, :ebx)          # next <= walker => chain exhausted
    @e.jbe(l_noret)
    @e.movl(:ebx, :edx)
    @e.jmp(l_scan)
    @e.local(l_noret)
    compile_eval_arg(scope, [:call, :__raise_return_error, []])  # raises; never returns
    @e.local(l_found)

    @e.movl(:eax,:ebp)
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
    @e.comment(Emitter::COMMENTS && "raise - unwind to exception handler")

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
    # Read #position ONCE (it was called twice: `arg.position != nil` then `p = arg.position`).
    if arg.respond_to?(:position) && (p = arg.position)
      # Compare position FIELDS instead of building arg.position.inspect (a fresh String) on every
      # expression just to detect a line/col change. This is the hottest codegen method, so that
      # per-expression inspect String was pure allocation + CPU on both hosts. @lastpos now holds the
      # last Position object itself.
      lp = @lastpos
      # Only line/file matter: @e.lineno emits a stabs marker solely on a LINE change (stabs N_SLINE is
      # line-based, no column), so a column-only change here just triggers a no-op @e.lineno + @lastpos
      # write per sub-expression on the same line. Dropping the col check leaves the emitted stabs identical
      # but skips that per-expression work in the hottest codegen method.
      if lp.nil? || p.lineno != lp.lineno || p.filename != lp.filename
        @e.lineno(p) if arg[0] != :defm
        @lastpos = p
      end
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
    elsif atype == :runtime_const
      # Runtime constant lookup for undefined constants
      # Call __const_get_global(const_name) which will trigger const_missing or raise NameError
      const_name_arg = const_name_to_string_ast(aparam.to_s)
      return Value.new(compile_eval_arg(scope, [:callm, :self, :__const_get_global, const_name_arg]), :object)
    end

    return Value.new(@e.load(atype, aparam), args.type)
  end


  # Compiles an assignment statement.
  def compile_assign(scope, left, right)
    # Handle anonymous splat assignment: (* = value)
    # This is a no-op assignment that just returns the value
    if left == :*
      return compile_eval_arg(scope, right)
    end

    # transform "foo.bar = baz" into "foo.bar=(baz)"
    # Also handle "foo&.bar = baz" (safe navigation in assignment context)
    # Also handle "foo[idx] = baz" -> "foo.[]=(idx, baz)"
    if left.is_a?(Array) && (left[0] == :callm || left[0] == :safe_callm)
      obj = left[1]
      method = left[2]
      setter_method = (method.to_s + "=").to_sym
      # Use regular callm even for safe_callm - in assignment context they're equivalent
      callm_method = :callm

      if left.size == 3  # no arguments: foo.bar = baz or foo&.bar = baz
        # The setter takes exactly the assigned value as its single argument. `right` is one expression
        # node (e.g. the `foo.m + 3` of a `foo.m += 3` op-assign), so it MUST be wrapped in an argument
        # list -- passing it bare made compile_callm iterate the node and treat its head (:callm) as an
        # argument ("undefined method 'callm'"). Mirrors the all_args wrapping in the has-arguments case.
        return compile_callm(scope, obj, setter_method, [right])
      else  # has arguments: foo[idx] = baz or foo.method(arg) = baz
        args = left[3] || []
        # args may be a single unwrapped AST node or an array of args. Wrap only when args[0]
        # is a node TAG (same rule as compile_callm's block-arg wrap): a one-element arg LIST
        # holding a plain variable (e.g. `@gen[y] ||= []`, args == [:y]) must NOT be wrapped --
        # doing so compiled the lvalue index as a method call on self ("undefined method 'y'").
        args = [args] if !args.is_a?(Array) ||
                         (args.length > 1 && args[0].is_a?(Symbol) &&
                          (@@keywords.include?(args[0]) || [:call, :callm, :safe_callm, :lambda, :proc].include?(args[0])))
        all_args = args + [right]
        return compile_callm(scope, obj, setter_method, all_args)
      end
    end

    # Handle Foo::Bar = value or self::Bar = value
    # These are static constant assignments, not method calls
    if left.is_a?(Array) && left[0] == :deref
      # [:deref, parent, const_name] = value -- scoped constant assignment.
      parent = left[1]
      const_name = left[2]
      pname = __deref_parent_name(parent)
      if pname
        # Register under the QUALIFIED key ("Outer::Inner::CONST"), matching the
        # __const_get read fallback. The old flatten-to-bare-name write made
        # reads of Scope::CONST assigned inside blocks/defs unresolvable.
        qualified = pname + "::" + const_name.to_s
        return compile_callm(scope, :self, :__const_set_global,
                             [const_name_to_string_ast(qualified), right])
      end
      # Dynamic parent (e.g. self::Const): keep the historical current-scope fallback.
      left = const_name
    end

    # Handle multiple assignment targets (destructuring after closure rewriting)
    # e.g., [[:index, :__env__, 9], [:index, :__env__, 8], :b] = value
    # This happens when nested destructuring has closure variables or symbols
    # Check: first element is an array (not a symbol operator) AND
    # the array looks like a list of targets (not a single expression like [:callm, ...])
    if left.is_a?(Array) && left.length > 1 && left[0].is_a?(Array) &&
       [:index, :deref].include?(left[0][0])
      # Unwrap single-element arrays that contain valid targets
      # Transform [[:index, :__env__, N]] to [:index, :__env__, N]
      left = left.collect do |t|
        if t.is_a?(Array) && t.length == 1 && t[0].is_a?(Array) && [:index, :deref].include?(t[0][0])
          t[0]  # Unwrap
        else
          t
        end
      end

      # Debug: check if this looks like a valid target list
      valid_targets = left.all? { |t| t.is_a?(Symbol) || (t.is_a?(Array) && [:index, :deref].include?(t[0])) }
      if !valid_targets
        # This array contains something that's not a simple target;
        # let it fall through to the error
      else
        # This is multiple assignment targets - we need to extract from right side array
        # and assign each element
        # Compile right side first
        source = compile_eval_arg(scope, right)
        @e.save_result(source)

        # For each target, extract the corresponding element and assign
        left.each_with_index do |target, idx|
          # Extract element: right[idx]
          @e.movl(source, :eax) if source.is_a?(Symbol)
          elem = compile_eval_arg(scope, [:callm, source.is_a?(Symbol) ? :eax : right, :[], [idx]])
          @e.save_result(elem)
          # Now assign to target
          compile_assign(scope, target, elem)
        end

        return Value.new([:subexpr], :object)
      end
    end

    source = compile_eval_arg(scope, right)
    atype = nil
    aparam = nil

    @e.pushl(source) if source.is_a?(Symbol) # Register

    args = get_arg(scope,left,:save)
    atype = args[0]  # FIXME: Ugly, but the compiler can't yet compile atype,aparem = get_arg ...
    aparam = args[1]
    atype = :addr if atype == :possible_callm

    # Handle runtime constant assignment - transform to method call
    if atype == :runtime_const
      # Pop the value from stack if needed
      if source.is_a?(Symbol)
        @e.popl(:eax)
        # A raw register symbol cannot ride the AST into compile_callm: an :eax argument is
        # compiled by get_arg as a NAME, emitting a `self.eax` dispatch -> method_missing 'eax'
        # (`def run_specs; SomeConst = 12; end` aborted language/class_spec this way). Spill the
        # value to a dedicated global (also a GC root) and reference THAT in the argument list.
        # Registered via add_global so output_global_init emits/initializes the storage.
        @global_scope.add_global(:__const_assign_tmp) if @global_scope
        @e.save_to_address(:eax, :__const_assign_tmp)
        source = [:sexp, :__const_assign_tmp]
      end

      # Transform to: __const_set_global(const_name, value)
      const_name_arg = const_name_to_string_ast(aparam.to_s)
      result = compile_callm(scope, :self, :__const_set_global, [const_name_arg, source])
      return Value.new(result, :object)
    end

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
    # Index loop, not exp.each: compile_do runs for every method/block/do body, and the block boxed a
    # closure per call on the self-hosted compiler (see the depth_first block-boxing finding).
    source = nil
    i = 0
    len = exp.length
    while i < len
      source = compile_eval_arg(scope, exp[i])
      @e.save_result(source)
      i += 1
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
  # rescue_clause can also be [:rescues, r1, r2, r3...] for multiple rescue clauses
  def compile_block(scope, args = [], exps = [], rescue_clause = nil, ensure_body = nil)
    # Handle multiple rescue clauses with dedicated method
    if rescue_clause && rescue_clause[0] == :rescues
      return compile_begin_rescues(scope, exps, rescue_clause[1..-1], ensure_body)
    end

    if rescue_clause || ensure_body
      compile_begin_rescue(scope, exps, rescue_clause, ensure_body)
    else
      compile_do(scope, *exps)
    end
  end

  # Compile begin block with multiple rescue clauses
  # rescue_clauses = [[:rescue, c1, v1, b1], [:rescue, c2, v2, b2], ...]
  # Transforms into nested rescues with conditional checks
  def compile_begin_rescues(scope, exps, rescue_clauses, ensure_body = nil)
    # Start with the last rescue clause and work backwards
    # Build nested structure: if exception.is_a?(RN) then ... elsif ... else raise end

    # Transform multiple rescues into a single rescue with conditional body
    # begin
    #   <exps>
    # rescue => __exc
    #   if __exc.is_a?(R1)
    #     v1 = __exc
    #     <b1>
    #   elsif __exc.is_a?(R2)
    #     v2 = __exc
    #     <b2>
    #   elsif ...
    #   else
    #     raise __exc
    #   end
    # ensure
    #   <ensure_body>
    # end

    # Build the conditional chain from the rescue clauses
    cond_body = build_rescue_conditional(rescue_clauses)

    # Create a single catch-all rescue clause with the conditional body
    rescue_clause = [:rescue, nil, :__exc__, cond_body]

    compile_begin_rescue(scope, exps, rescue_clause, ensure_body)
  end

  # Build conditional chain for multiple rescue clauses
  # Returns array of statements to execute in rescue handler
  def build_rescue_conditional(rescue_clauses)
    return [] if rescue_clauses.empty?

    # Start with the last rescue clause
    last = rescue_clauses.last
    last_class = last[1]
    last_var = last[2]
    last_body = last[3]

    # Build else clause: raise __exc__
    else_clause = [:raise, :__exc__]

    # Build then-branch for last rescue
    # Wrap multiple statements in :do node for compile_if
    last_statements = (last_var ? [[:assign, last_var, :__exc__]] : []) + (last_body || [])
    last_then = last_statements.size == 1 ? last_statements[0] : ([:do] + last_statements)

    last_cond = if last_class
      [:if,
       [:callm, :__exc__, :is_a?, [last_class]],
       last_then,
       else_clause]
    else
      # No class means catch all
      last_then
    end

    # Work backwards through remaining rescue clauses
    result = last_cond
    (rescue_clauses.size - 2).downto(0) do |i|
      r = rescue_clauses[i]
      r_class = r[1]
      r_var = r[2]
      r_body = r[3]

      # Build then-branch: wrap multiple statements in :do
      statements = (r_var ? [[:assign, r_var, :__exc__]] : []) + (r_body || [])
      then_branch = statements.size == 1 ? statements[0] : ([:do] + statements)

      # Build: if __exc.is_a?(r_class); then_branch; else <result> end
      result = if r_class
        [:if,
         [:callm, :__exc__, :is_a?, [r_class]],
         then_branch,
         result]  # result is already a single expression
      else
        # No class means catch all - should be last, but handle it anyway
        then_branch
      end
    end

    # Return as array of statements
    [result]
  end

  # Compile begin...rescue...else...ensure...end block
  # rescue_clause = [:rescue, exception_class, var_name, body] or
  #                 [:rescue, exception_class, var_name, body, else_body]
  # ensure_body = expressions to run in all cases (nil if not present)
  def compile_begin_rescue(scope, exps, rescue_clause, ensure_body = nil)
    # Handle ensure-only blocks (no rescue)
    if !rescue_clause && ensure_body
      # Track the enclosing ensure for `return` inside the body: compile_return unwinds
      # @ensure_stack so the ensure code runs before the frame is torn down (Ruby semantics --
      # language/return_spec's begin/return/ensure-in-a-lambda). Function bodies compile
      # DEFERRED (compile_defun registers them; output_functions emits later), so contexts
      # never leak across functions.
      @ensure_stack ||= []
      @ensure_stack.push([ensure_body, false])
      compile_do(scope, *exps)
      @ensure_stack.pop
      # Save result before ensure clause (ensure might overwrite eax)
      @e.pushl(:eax)
      compile_do(scope, *ensure_body)
      # Restore result after ensure clause
      @e.popl(:eax)
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

    # Build variable list for let() - include rescue_var only if it's a simple symbol
    # Complex lvalues like self.foo or @ivar will be assigned via compile_assign later.
    # Do NOT re-declare it here when it is already a local of an enclosing scope (find_vars registers every
    # rescue variable there): a fresh let-local would SHADOW the outer one, so `rescue => e` would bind a
    # throwaway that vanishes at the end of the block, leaving the outer `e` unchanged (Ruby keeps the
    # assignment visible after the begin/rescue).
    let_vars = [:__handler, :__exc]
    if rescue_var && rescue_var.is_a?(Symbol)
      existing = scope.get_arg(rescue_var)
      let_vars << rescue_var if !(existing && (existing[0] == :lvar || existing[0] == :arg))
    end

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

      # Compile try block -- its result is the value of the whole begin unless an else clause is present
      # (an else REPLACES the body value in Ruby). Track the handler + ensure for `return`
      # inside the body (see the ensure-only path above): the return must pop this handler and
      # run the ensure before leaving the frame, or the handler goes stale (later raises unwind
      # into a dead frame) and the ensure is skipped.
      @ensure_stack ||= []
      @ensure_stack.push([ensure_body, true])
      compile_do(lscope, *exps)
      @ensure_stack.pop

      if else_body
        # else runs only on no-exception and is NOT protected by the rescue, so pop the handler first,
        # then run else; its result becomes the value (the body result is intentionally discarded).
        compile_eval_arg(lscope, [:callm, :$__exception_runtime, :pop_handler])
        compile_do(lscope, *else_body)
      else
        # The body result is the value; pop_handler returns a value and would clobber eax, so save the
        # body result across it. (This was the bug: pop_handler overwrote eax before it was saved, so a
        # `x = begin V rescue .. ensure .. end` evaluated to nil instead of V.)
        @e.pushl(:eax)
        compile_eval_arg(lscope, [:callm, :$__exception_runtime, :pop_handler])
        @e.popl(:eax)
      end

      # Execute ensure clause if present (always runs on normal completion) without disturbing the value.
      if ensure_body
        @e.pushl(:eax)
        compile_do(lscope, *ensure_body)
        @e.popl(:eax)
      end

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

      # Save result before clear (clear overwrites eax with its return value)
      @e.pushl(:eax)

      # Clear exception from singleton
      compile_eval_arg(lscope, [:callm, :$__exception_runtime, :clear])

      # Restore result after clear
      @e.popl(:eax)

      # Save result again if ensure clause present (ensure might overwrite eax)
      if ensure_body
        @e.pushl(:eax)
      end

      # Execute ensure clause if present (always runs even after rescue)
      compile_do(lscope, *ensure_body) if ensure_body

      # Restore result after ensure clause
      if ensure_body
        @e.popl(:eax)
      end

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
    const_off = nil
    r = @e.with_register do |reg|
      @e.movl(source, reg)
      if index.is_a?(Numeric)
        # Fold a constant index into displacement addressing at the deref site (off(%reg)) instead of
        # emitting `addl index*4, %reg` and dereferencing (%reg). Saves an instruction per slot access and
        # leaves %reg = base. reg is scratch (with_register) so nothing relies on it holding base+off.
        const_off = index * 4
      else
        @e.pushl(reg)
        source = compile_eval_arg(scope, index)
        @e.save_result(source)
        @e.sall(2, @e.result_value)
        @e.popl(reg)
        @e.addl(@e.result_value, reg)
      end
    end
    if const_off && const_off != 0
      return Value.new([:indirect_disp, [r, const_off]], lookup_type(arr,index))
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
    # A require whose target file does not exist reaches here as a :require_missing marker. The
    # scope tells us the context: scope.method walks the scope chain and is non-nil only when an
    # enclosing method/block/lambda exists. Inside such a runtime context an unresolved require is a
    # runtime LoadError (compile it so the program raises when that path executes); at the top level
    # (or a class/module body), where there is no enclosing method, it is a real build error.
    if exp.is_a?(Array) && exp[0] == :require_missing
      q = exp[1]
      if scope.method
        return compile_exp(scope, [:call, :raise, [:LoadError, "cannot load such file -- #{q}"]])
      end
      error("Unable to open '#{q}'")
    end
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

    # check if exp is within predefined keywords list

    # NOTE: the bare `exp` below is a load-bearing self-host workaround
    # (lifting the variable before the dynamic send); do not remove.
    exp
    if(@@keywords.include?(exp[0]))
      # Cache the "compile_<kw>" dispatch name per node type (~30 keywords): it was rebuilt as a fresh
      # String on every keyword node. Explicit []=, not ||= (the op-assign index form returns nil self-hosted).
      mname = @compile_names[exp[0]]
      if !mname
        mname = "compile_#{exp[0].to_s}"
        @compile_names[exp[0]] = mname
      end
      return self.send(mname, scope, *exp.rest)
    elsif @@oper_methods.member?(exp[0])
      return compile_callm(scope, exp[1], exp[0], exp[2..-1])
    else
      return compile_call(scope, exp[1], exp[2],exp[3], pos) if (exp[0] == :call)
      return compile_callm(scope, exp[1], exp[2], exp[3], exp[4]) if (exp[0] == :callm)
      return compile_safe_callm(scope, exp[1], exp[2], exp[3], exp[4]) if (exp[0] == :safe_callm)
      # Only treat as function call if exp[0] is a Symbol (function name)
      # If exp[0] is an array, it's a list of statements to execute in sequence
      if exp.is_a?(Array) && exp[0].is_a?(Symbol)
        return compile_call(scope, exp[0], exp.rest, nil, pos)
      elsif exp.is_a?(Array) && exp[0].is_a?(Array)
        # List of statements - compile each one in sequence (like compile_do)
        return compile_do(scope, *exp)
      end
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

      # Start the garbage collector before ANY allocation. tgc_start must precede the first tgc_add: it sets
      # the stack bottom + static-root range and a non-zero loadfactor (without it the GC's slot table never
      # grows, so tgc_add_ptr does `% nslots` with nslots==0 -> SIGFPE on the very first allocation). It used
      # to live at base.rb top-level, but the user program's top-level runs before lib/core, so a top-level
      # closure's env was allocated first and crashed. main's frame here is the true stack bottom.
      # (Paired with the tgc_add/tgc_realloc/tgc_stop wiring in lib/core/base.rb.)
      compile_eval_arg(@global_scope, [:sexp, [:tgc_start, :__stack_top, :__roots_start, :__roots_end]])

      # Initialize all global variables (starting with $) to nil
      @global_scope.globals.keys.each do |g|
        if g.to_s[0] == ?$
          compile_eval_arg(@global_scope, [:assign, g, :nil])
        end
      end

      compile_eval_arg(@global_scope, exp)
      # Run at_exit handlers on normal termination too (Kernel#exit runs them for the explicit-exit path).
      # Use a plain method call for the handlers, then the raw exit syscall -- routing the terminator
      # through Kernel#exit itself (a callm in main's epilogue context) segfaulted.
      compile_eval_arg(@global_scope, [:call, :__run_at_exit, []])
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
      # Land in Object#__dispatch_missing__ (runtime define_method registry, then method_missing).
      # The stack is already arranged exactly like a normal method call.
      @e.jmp("*__voff____dispatch_missing__(%eax)")

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

    @e.comment(Emitter::COMMENTS && "")
  end

  # Emit the runtime ivar reflection table that backs instance_variable_get/set/instance_variables.
  # Ivar slots are assigned statically (classcope.rb) with no runtime name->slot map; this table is
  # that map, keyed by the class fq-name cstr held in each class object's slot 2 (compile_class.rb:745).
  # Layout: a flat array of rows, each 3 longs -- (fqname_cstr, ivar_name_cstr, RAW slot offset) -- plus
  # a count cell. Emitted for EVERY class in @classes (each @classes key.to_s equals the string written
  # to that class's slot 2, so a duplicate-key alias just yields harmless never-matched rows). The lookup
  # is __ivar_offset in lib/core/object.rb. Always emitted (even with 0 rows) so lib/core's references to
  # __ivar_table/__ivar_table_count link.
  # EVERY declared ivar is emitted -- reflectability is NOT decided here by name. Built-in classes store
  # RAW (untagged) machine values in some ivars (Array's element pointer/length, String's byte buffer,
  # Hash's table, Proc's code address, ...); MRI hides such internals. Here that hiding is decided PER
  # CLASS at reflection time by Object#__hidden_ivars (lib/core/object.rb): #instance_variables skips a
  # class's own hidden ivars before dereferencing them. A global name list cannot do this correctly -- the
  # same name may be a legitimate user ivar on another class.
  def output_ivar_table
    seen = {}
    rows = []
    @classes.each do |key, cscope|
      next unless cscope.respond_to?(:all_ivar_offsets)
      fqn = key.to_s
      cscope.all_ivar_offsets.each do |ivar, off|
        # Reflect EVERY declared instance variable -- no name-based exclusion. A name (even @__foo or a
        # name that collides with a core class's internal ivar) can NOT decide reflectability; only the
        # owning class can. Core classes hide their own internal ivars per-class via Object#__hidden_ivars
        # (see lib/core/object.rb), which is consulted at reflection time by #instance_variables.
        dedup = fqn + "\0" + ivar.to_s
        next if seen[dedup]
        seen[dedup] = true
        rows << [fqn, ivar.to_s, off]
      end
    end
    @e.label("__ivar_table")
    rows.each do |fqn, ivar, off|
      @e.emit(".long", strconst(fqn).last)
      @e.emit(".long", strconst(ivar).last)
      @e.long(off)
    end
    @e.label("__ivar_table_count")
    @e.long(rows.length)
    @e.comment(Emitter::COMMENTS && "")
  end

  # Emit a runtime constant reflection table so Object.const_get / const_defined? / __const_get_global
  # can resolve STATICALLY-compiled top-level constants (classes, modules, CONST=...) -- previously they
  # found only runtime-registered constants (__const_set_global), so const_get("String")/("Foo") raised.
  # Each row is 2 longs: (name_cstr, &global_cell). The value lives IN the cell (a class object pointer or
  # a tagged immediate), populated at program init, so the lookup (kernel.rb __runtime_const_lookup)
  # dereferences the cell. Only bare top-level names are registered here (nested "Foo::Bar" resolution is
  # a follow-up; "__"-qualified names are skipped to avoid the __ vs :: convention mismatch).
  def output_const_table
    rows = []
    seen = {}
    @global_constants.to_a.each do |c|
      cs = c.to_s
      next if cs.empty?
      # Register nested constants under their flattened "Parent__Child" name too (was skipped): that is
      # exactly the name a class carries in slot 2 / returns from #name, so `Object.const_get("AST__Expr")`
      # resolves it -- needed for Marshal.load of nested classes (AST::Expr, Scanner::Position, ...). The
      # spec-facing "Parent::Child" form resolves stepwise via const_get's "::" split (separate concern).
      # getbyte, not cs[0]: the self-hosted String#[] returns an Integer byte (not a 1-char String), so a
      # `>= "A"` char comparison raises "comparison of Integer with String" under selftest-c. 65/90 = A/Z.
      first = cs.getbyte(0)
      next unless first >= 65 && first <= 90   # a constant name (A-Z)
      next if seen[cs]
      seen[cs] = true
      rows << cs
    end
    @e.label("__const_table")
    rows.each do |cs|
      @e.emit(".long", strconst(cs).last)   # constant name cstr
      @e.emit(".long", cs)                   # address of the global cell holding the value
    end
    @e.label("__const_table_count")
    @e.long(rows.length)
    @e.comment(Emitter::COMMENTS && "")
  end

  # Output function to initialize global variables to nil if still uninitialized (0)
  def output_global_init
    @e.export("__init_globals", "function")
    @e.label("__init_globals")
    @e.emit(".LFBB__init_globals:")

    # Initialize to nil (if still raw 0) any global that must read as nil when never assigned:
    #  - user Ruby globals ($foo and top-level @ivars). Their storage symbol has the $/@ already stripped
    #    (globalscope get_arg), so they are tracked in a dedicated user_globals set -- the old check for a
    #    leading '$' here never matched and these were left as raw 0, so `$x.foo`/`@x.foo` on an unset
    #    global SIGSEGV'd (method dispatch dereferences the null "object"). Only user globals are touched;
    #    internal __ globals used as raw values are left alone (nil-initing all of .bss was tried and
    #    reverted for breaking raw-0-as-falsy on internal data).
    #  - class-object ivars (__classivar__*) that back `@x` in `def self.foo` (same raw-0 hazard).
    names = @global_scope.user_globals.keys.collect { |g| g.to_s }
    @global_scope.globals.keys.each do |g|
      gs = g.to_s
      names << gs if gs.start_with?("__classivar__")
    end

    names.uniq.each do |name|
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

    @e.ret
  end

  # Pre-scan the AST to register all statically-defined constants
  # This ensures that constants defined anywhere in the code are marked as "known"
  # before compilation, so references to them remain static.
  # scope_path: array of scope names building qualified name (e.g., ["ConstantSpecs", "ModuleA"])
  def scan_and_register_constants(exp, scope_path = [])
    return unless exp.is_a?(Array)
    return if exp.empty?

    case exp[0]
    when :class, :module
      # Extract class/module name and build new scope path
      if exp[1].is_a?(Symbol)
        # Simple class name
        # Register only the actual BSS name: qualified if nested, bare if top-level
        if !scope_path.empty?
          @global_scope.register_constant((scope_path + [exp[1]]).join("__").to_sym)
        else
          @global_scope.register_constant(exp[1])
        end
        # Recursively scan the class/module body with new scope path
        i = 3
        while i < exp.length
          scan_and_register_constants(exp[i], scope_path + [exp[1].to_s]) if exp[i]
          i = i + 1
        end
      elsif exp[1].is_a?(Array) && exp[1][0] == :deref
        # Handle nested names like Foo::Bar - extract parts
        parts = []
        n = exp[1]
        while n.is_a?(Array) && n[0] == :deref && n.length == 3
          parts.unshift(n[2]) if n[2].is_a?(Symbol)
          n = n[1]
        end
        parts.unshift(n) if n.is_a?(Symbol)
        if parts.any?
          # Register only the actual BSS name: qualified if nested, bare if top-level
          if !scope_path.empty?
            @global_scope.register_constant((scope_path + [parts.join("__")]).join("__").to_sym)
          else
            @global_scope.register_constant(parts.join("__").to_sym)
          end
          # Recursively scan the class/module body with new scope path
          i = 3
          while i < exp.length
            scan_and_register_constants(exp[i], scope_path + [parts.join("__")]) if exp[i]
            i = i + 1
          end
        end
      else
        # Singleton class (class << obj) - scan body without changing scope path
        # Constants defined here should be registered at current scope level
        i = 3
        while i < exp.length
          scan_and_register_constants(exp[i], scope_path) if exp[i]
          i = i + 1
        end
      end

    when :assign
      # Register constant assignments
      if exp[1].is_a?(Symbol) && exp[1].to_s[0] && exp[1].to_s[0] >= ?A && exp[1].to_s[0] <= ?Z
        # Register only the actual BSS name: qualified if nested, bare if top-level
        if !scope_path.empty?
          @global_scope.register_constant((scope_path + [exp[1].to_s]).join("__").to_sym)
        else
          @global_scope.register_constant(exp[1])
        end
      elsif exp[1].is_a?(Array) && exp[1][0] == :destruct
        # Handle destructuring: (A, B) = values
        i = 1
        while i < exp[1].length
          if exp[1][i].is_a?(Symbol) && exp[1][i].to_s[0] && exp[1][i].to_s[0] >= ?A && exp[1][i].to_s[0] <= ?Z
            # Register only the actual BSS name: qualified if nested, bare if top-level
            if !scope_path.empty?
              @global_scope.register_constant((scope_path + [exp[1][i].to_s]).join("__").to_sym)
            else
              @global_scope.register_constant(exp[1][i])
            end
          elsif exp[1][i].is_a?(Array) && exp[1][i][0] == :destruct
            # Nested destructuring - recursively process
            scan_and_register_constants([:assign, exp[1][i], nil], scope_path)
          end
          # Skip :deref patterns - those are runtime assignments
          i = i + 1
        end
      end
      # Recursively scan the right side (preserve scope path)
      scan_and_register_constants(exp[2], scope_path) if exp[2]

    when :defm, :defs
      # Skip scanning method bodies - constants assigned in methods are dynamically
      # executed and should use runtime lookup, not static :addr references
      # (They will get Object prefix added by compile_assign, but aren't in GlobalScope)
      return

    when :do, :block, :sexp
      # Recursively scan all sub-expressions (preserve scope path)
      i = 1
      while i < exp.length
        scan_and_register_constants(exp[i], scope_path) if exp[i]
        i = i + 1
      end

    else
      # For all other expression types, recursively scan (preserve scope path)
      i = 0
      while i < exp.length
        e = exp[i]
        scan_and_register_constants(e, scope_path) if e.is_a?(Array)
        i = i + 1
      end
    end
  end

  # Starts the actual compile process.
  def compile exp
    alloc_vtable_offsets(exp)
    scan_and_register_constants(exp)  # Pre-scan to register all constants

    # Rewrite "expr rescue fallback" modifiers into begin/rescue blocks before compilation.
    rewrite_rescue_mod(exp)

    # Transform pattern matching to when clauses
    # NOTE: This runs AFTER preprocess(), so pattern-bound variables won't be captured
    # in __env__ for nested closures. See docs/KNOWN_ISSUES.md and transform.rb:rewrite_pattern_matching
    rewrite_pattern_matching(exp)

    compile_main(exp)
    # after the main function, we ouput all functions and constants
    # used and defined so far.
    output_functions
    # Shared fixed-arity error handlers (collected during output_functions). Emitted here while still in
    # .text, right after the functions whose arity checks jump to them.
    output_arity_fail_handlers
    # output_global_init must run AFTER output_functions -- class-object ivars (__classivar__*) are only
    # registered as globals while their method bodies compile in output_functions, and the init routine
    # has to see them to zero->nil them -- but BEFORE the vtable/constants output, which switches to the
    # .data/.bss section (output_global_init emits .text code and relies on being left in .text here).
    # __init_globals is a separate function called at startup, so emitting its body here is fine.
    output_global_init
    output_vtable_thunks
    output_vtable_names
    output_ivar_table
    output_const_table
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
