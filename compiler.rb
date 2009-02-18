#!/bin/env ruby

require 'emitter'
require 'parser'

DO_BEFORE= [ 
  [:defun, :array, [:size],[:malloc,[:mul,:size,4]]]
]
DO_AFTER= []

class Arg
  attr_reader :name,:rest
  def initialize name, *modifiers
    @name = name
    modifiers.each do |m|
      @rest = true if m == :rest
    end
  end

  def rest?; @rest; end  
  def type
    rest? ? :argaddr : :arg
  end
end

class Function
  attr_reader :args,:body
  def initialize args,body
    @body = body
    @rest = false
    @args = args.collect do |a|
      arg = Arg.new(*[a].flatten)
      @rest = true if arg.rest?
      arg
    end
  end

  def rest?; @rest; end
  def get_arg(a)
    if a == :numargs
      # This is a bit of a hack, but it turns :numargs
      # into a constant for any non-variadic function
      return rest? ? [:lvar,-1] : [:int,args.size]
    end

    args.each_with_index do |arg,i|
      return [arg.type,i] if arg.name == a
    end

    return nil
  end
end

class Scope
  def initialize compiler,func
    @c = compiler
    @func = func
  end

  def rest?
    @func ? @func.rest? : false
  end

  def get_arg a
    a = a.to_sym
    if @func
      arg = @func.get_arg(a)
      return arg if arg
    end
    return [:addr,a]
  end
end

class LocalVarScope
  def initialize locals, next_scope
    @next = next_scope
    @locals = locals
  end

  def rest?
    @next ? @next.rest? : false
  end

  def get_arg a
    a = a.to_sym
    return [:lvar,@locals[a] + (rest? ? 1 : 0)] if @locals.include?(a)
    return @next.get_arg(a) if @next
    return [:addr,a] # Shouldn't get here normally
  end
end

class Compiler
  attr_reader :global_functions

  def initialize
    @e = Emitter.new
    @global_functions = {}
    @string_constants = {}
  end

  def get_arg(scope,a)
    return compile_exp(scope,a) if a.is_a?(Array)
    return [:int, a] if (a.is_a?(Fixnum))
    return scope.get_arg(a) if (a.is_a?(Symbol))

    lab = @string_constants[a]
    if !lab
      lab = @e.get_local
      @string_constants[a] = lab
    end
    return [:strconst,lab]
  end

  def output_constants
    @e.rodata { @string_constants.each { |c,l| @e.string(l,c) } }
  end

  def output_functions
    @global_functions.each do |name,func|
      @e.func(name, func.rest?) { compile_eval_arg(Scope.new(self,func),func.body) }
    end
  end

  def compile_defun scope,name, args, body
    @global_functions[name] = Function.new(args,body)
    return [:addr,name]
  end

  def compile_ifelse scope,cond, if_arm,else_arm = nil
    compile_exp(scope,cond)
    l_else_arm = @e.get_local
    l_end_if_arm = @e.get_local
    @e.jmp_on_false(l_else_arm)
    compile_exp(scope,if_arm)
    @e.jmp(l_end_if_arm) if else_arm
    @e.local(l_else_arm)
    compile_exp(scope,else_arm) if else_arm
    @e.local(l_end_if_arm) if else_arm
    return [:subexpr]
  end

  def compile_lambda scope,args, body
    compile_defun(scope,@e.get_local, args,body)
  end

  def compile_eval_arg scope,arg
    atype, aparam = get_arg(scope,arg)
    return aparam if atype == :int
    return @e.addr_value(aparam) if atype == :strconst
    case atype
    when :argaddr:
        @e.load_arg_address(aparam)
    when :addr
      @e.load_address(aparam)
    when :indirect
      @e.emit(:movl,"(%#{aparam.to_s})",@e.result_value)
    when :arg
      @e.load_arg(aparam)
    when :lvar
      @e.load_local_var(aparam)
    else
    end
    return @e.result_value
  end

  def compile_assign scope, left, right
    source = compile_eval_arg(scope, right)
    @e.pushl(source)
    atype, aparam = get_arg(scope,left)
    if atype == :indirect
      @e.popl(:eax)
      @e.emit(:movl,source,"(%#{aparam})")
    elsif atype == :lvar
      @e.popl(:eax)
      @e.save_to_local_var(source,aparam)
    elsif atype == :arg
      @e.popl(:eax)
      @e.save_to_arg(source,aparam)
    else
      raise "Expected an argument on left hand side of assignment" 
    end
    return [:subexpr]
  end

  def compile_call scope,func, args
    @e.with_stack(args.length,true) do
      args.each_with_index do |a,i| 
        param = compile_eval_arg(scope,a)
        @e.save_to_stack(param,i)
      end
      @e.call(compile_eval_arg(scope,func))
    end
    return [:subexpr]
  end

  def compile_do(scope,*exp)
    exp.each { |e| source=compile_eval_arg(scope,e); @e.save_result(source); }
    return [:subexpr]
  end

  def compile_index scope,arr,index
    source = compile_eval_arg(scope, arr)
    @e.movl(source,:edx)
    source = compile_eval_arg(scope, index)
    @e.save_result(source)
    @e.sall(2,:eax)
    @e.addl(:eax,:edx)
    return [:indirect,:edx]
  end

  def compile_while(scope, cond, body)
    @e.loop do |br|
      var = compile_eval_arg(scope,cond)
      @e.jmp_on_false(br)
      compile_exp(scope,body)
    end
    return [:subexpr]
  end

  def compile_let(scope,varlist,*args)
    vars = {}
    varlist.each_with_index {|v,i| vars[v]=i}
    ls = LocalVarScope.new(vars,scope)
    if vars.size
      @e.with_local(vars.size) { compile_do(ls,*args) }
    else
      compile_do(ls,*args)
    end
  end

  def compile_exp(scope,exp)
    return if !exp || exp.size == 0
    return compile_do(scope,*exp[1..-1]) if exp[0] == :do 
    return compile_defun(scope,*exp[1..-1]) if (exp[0] == :defun)
    return compile_ifelse(scope,*exp[1..-1]) if (exp[0] == :if)
    return compile_lambda(scope,*exp[1..-1]) if (exp[0] == :lambda)
    return compile_assign(scope,*exp[1..-1]) if (exp[0] == :assign) 
    return compile_while(scope,*exp[1..-1]) if (exp[0] == :while)
    return compile_index(scope,*exp[1..-1]) if (exp[0] == :index)
    return compile_let(scope,*exp[1..-1]) if (exp[0] == :let)
    return compile_call(scope,exp[1],exp[2]) if (exp[0] == :call)
    return compile_call(scope,exp[0],exp[1..-1]) if (exp.is_a? Array)
    STDERR.puts "Somewhere calling #compile_exp when they should be calling #compile_eval_arg? #{exp.inspect}"
    res = compile_eval_arg(scope,exp[0])
    @e.save_result(res)
    return [:subexpr]
  end

  def compile_main(exp)
    @e.main do
      # We should allow arguments to main
      # so argc and argv get defined, but
      # that is for later.
      @main = Function.new([],[])
      compile_eval_arg(Scope.new(self,@main),exp)
    end

    output_functions
    output_constants
  end

  def compile(exp) 
    compile_main([:do, DO_BEFORE, exp, DO_AFTER]) 
  end  
end

s = Scanner.new(STDIN)
prog = nil

dump = false
ARGV.each do |opt|
  dump = true if opt == "--parsetree"
end  

begin
  prog = Parser.new(s).parse
rescue Exception => e
  STDERR.puts "#{e.message}"
  STDERR.puts "Failed before:\n"
  buf = ""
  while s.peek && buf.size < 100
    buf += s.get
  end
  STDERR.puts buf
end

if prog && dump
  PP.pp prog 
  exit
end

Compiler.new.compile(prog) if prog
