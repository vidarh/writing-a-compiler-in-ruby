#!/bin/env ruby

require 'emitter'
require 'parser'
require 'scope'
require 'function'

require 'set'

DO_BEFORE= [ 
  [:defun, :array, [:size],[:malloc,[:mul,:size,4]]],
]
DO_AFTER= []

class Compiler
  attr_reader :global_functions

  def initialize
    @e = Emitter.new
    @global_functions = {}
    @string_constants = {}
    @global_constants = Set.new
    @classes = {}
    @vtableoffsets = VTableOffsets.new
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
    @e.bss    { @global_constants.each { |c|   @e.bsslong(c) }}
  end

  def output_functions
    @global_functions.each do |name,func|
      @e.func(name, func.rest?) { compile_eval_arg(FuncScope.new(func,@global_scope),func.body) }
    end
  end

  def compile_defun scope,name, args, body
    if scope.is_a?(ClassScope) # Ugly. Create a default "register_function" or something. Have it return the global name
      f = Function.new([:self]+args,body) # "self" is "faked" as an argument to class methods.
      @e.comment("method #{name}")
      fname = "__method_#{scope.name}_#{name}"
      scope.set_vtable_entry(name,fname,f)
      @e.load_address(fname)
      @e.movl(scope.name.to_s,:edx)
      v = scope.vtable[name]
      @e.addl(v.offset*Emitter::PTR_SIZE,:edx) if v.offset > 0
      @e.movl(@e.result_value,"(%edx)")
      name = fname
    else
      f = Function.new(args,body)
    end
    @global_functions[name] = f
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
    when :argaddr
      @e.load_arg_address(aparam)
    when :addr
      @e.load_address(aparam)
    when :indirect
      @e.emit(:movl,"(%#{aparam.to_s})",@e.result_value)
    when :arg
      @e.load_arg(aparam)
    when :lvar
      @e.load_local_var(aparam)
    when :global
      @e.emit(:movl,aparam.to_s,@e.result_value)
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
    elsif atype == :global
      @e.popl(:eax)
      @e.emit(:movl,source,aparam.to_s)
    elsif atype == :lvar
      @e.popl(:eax)
      @e.save_to_local_var(source,aparam)
    elsif atype == :arg
      @e.popl(:eax)
      @e.save_to_arg(source,aparam)
    else
      raise "Expected an argument on left hand side of assignment - got #{atype.to_s}" 
    end
    return [:subexpr]
  end

  def compile_call scope,func, args
    args = [args] if !args.is_a?(Array)
    @e.with_stack(args.length,true) do
      args.each_with_index do |a,i| 
        param = compile_eval_arg(scope,a)
        @e.save_to_stack(param,i)
      end
      @e.call(compile_eval_arg(scope,func))
    end
    return [:subexpr]
  end

  def compile_callm scope,ob,method, args
    @e.comment("callm #{ob.to_s}.#{method.to_s}")
    args ||= []
    @e.with_stack(args.length+1,true) do
      ret = compile_eval_arg(scope,ob)
      @e.movl(ret,:eax) if ret != :eax
      @e.save_to_stack(:eax,0)
      args.each_with_index do |a,i| 
        param = compile_eval_arg(scope,a)
        @e.save_to_stack(param,i+1)
      end
      @e.movl("(%esp)",:eax)
      @e.movl("(%eax)",:edx)
      off = @vtableoffsets.get_offset(method)
      raise "No offset for #{method}, and we don't yet implement send" if !off
      @e.movl("#{off*Emitter::PTR_SIZE}(%edx)",:eax)
      @e.call(:eax)
    end
    @e.comment("callm #{ob.to_s}.#{method.to_s} END")
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

  def compile_class(scope,name,*exps)
    @e.comment("=== class #{name} ===")
    cscope = ClassScope.new(scope,name,@vtableoffsets)
    # FIXME: (If this class has a superclass, copy the vtable from the superclass as a starting point)
    # FIXME: Fill in all unused vtable slots with __method_missing
    # FIXME: Fill in slot 0 with the Class vtable.
    exps.each do |l2|
      l2.each do |e|
        if e.is_a?(Array) && e[0] == :defun
          cscope.add_vtable_entry(e[1])
        end
      end
    end
    @classes[name] = cscope
    @global_scope.globals << name
    compile_exp(scope,[:assign,name.to_sym,[:call,:__new_class_object,[cscope.klass_size]]])
    @global_constants << name
    exps.each do |e|
      addr = compile_do(cscope,*e)
    end
    @e.comment("=== end class #{name} ===")
  end

  def compile_exp(scope,exp)
    return if !exp || exp.size == 0
    return compile_do(scope,*exp[1..-1]) if exp[0] == :do 
    return compile_class(scope,*exp[1..-1]) if (exp[0] == :class)
    return compile_defun(scope,*exp[1..-1]) if (exp[0] == :defun)
    return compile_ifelse(scope,*exp[1..-1]) if (exp[0] == :if)
    return compile_lambda(scope,*exp[1..-1]) if (exp[0] == :lambda)
    return compile_assign(scope,*exp[1..-1]) if (exp[0] == :assign) 
    return compile_while(scope,*exp[1..-1]) if (exp[0] == :while)
    return compile_index(scope,*exp[1..-1]) if (exp[0] == :index)
    return compile_let(scope,*exp[1..-1]) if (exp[0] == :let)
    return compile_call(scope,exp[1],exp[2]) if (exp[0] == :call)
    return compile_callm(scope,exp[1],exp[2],exp[3]) if (exp[0] == :callm)
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
      @global_scope = GlobalScope.new
      compile_eval_arg(FuncScope.new(@main,@global_scope),exp)
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
