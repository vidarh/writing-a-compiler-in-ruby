#!/bin/env ruby

DO_BEFORE= []

DO_AFTER= []


class Compiler
  PTR_SIZE=4

  def initialize
    @global_functions = {}
    @string_constants = {}
    @seq = 0
  end

  def get_arg(a)
    # Handle strings or subexpressions 
    return compile_exp(a) if a.is_a?(Array)
    return [:int, a] if (a.is_a?(Fixnum)) 
    return [:atom, a] if (a.is_a?(Symbol))

    seq = @string_constants[a]
    return seq if seq
    seq = @seq
    @seq += 1
    @string_constants[a] = seq
    return [:strconst,seq]
  end

  def output_constants
    puts "\t.section .rodata"
    @string_constants.each do |c,seq|
      puts ".LC#{seq}:"
      puts "\t.string \"#{c}\""
    end
  end

 def output_functions
    @global_functions.each do |name,data|
     puts ".globl #{name}"
     puts ".type   #{name}, @function"
     puts "#{name}:"
     puts "\tpushl   %ebp"
     puts "\tmovl    %esp, %ebp"
     compile_exp(data[1])
     puts "\tleave"
     puts "\tret"
     puts "\t.size   #{name}, .-#{name}"
     puts
    end
  end

  def compile_defun name, args, body
    @global_functions[name] = [args,body]
    return [:subexpr]
  end

  def compile_ifelse cond, if_arm,else_arm 
    compile_exp(cond) 
    puts "\ttestl\t%eax, %eax" 
    else_arm_seq = @seq
    end_if_arm_seq = @seq + 1
    @seq += 2 
    puts "\tje\t.L#{else_arm_seq}" 
    compile_exp(if_arm) 
    puts "\tjmp\t.L#{end_if_arm_seq}" 
    puts ".L#{else_arm_seq}:" 
    compile_exp(else_arm) 
    puts ".L#{end_if_arm_seq}:" 
    return [:subexpr]
  end 

  def compile_lambda args, body
    name = "lambda__#{@seq}"
    @seq += 1
    compile_defun(name, args,body)
    puts "\tmovl\t$#{name},%eax"
    return [:subexpr]
  end

  def compile_eval_arg arg
    atype, aparam = get_arg(arg)
    return "$.LC#{aparam}" if atype == :strconst
    return "$#{aparam}" if atype == :int
    return aparam.to_s if atype == :atom
    return "%eax"
  end

  def compile_call func, args
    stack_adjustment = PTR_SIZE + (((args.length+0.5)*PTR_SIZE/(4.0*PTR_SIZE)).round) * (4*PTR_SIZE)

    puts "\tsubl\t$#{stack_adjustment}, %esp"
    args.each_with_index do |a,i| 
      param = compile_eval_arg(a)
      puts "\tmovl\t#{param},#{i>0 ? i*4 : ""}(%esp)"
    end

    res = compile_eval_arg(func) 
    res = "*%eax" if res == "%eax" # Ugly. Would be nicer to retain some knowledge of what "res" contains
    puts "\tcall\t#{res}"
    puts "\taddl\t$#{stack_adjustment}, %esp"
    return [:subexpr]
  end

  def compile_do(*exp)
    exp.each { |e| compile_exp(e) } 
    return [:subexpr]
  end

  def compile_exp(exp)
    return if !exp || exp.size == 0
    return compile_do(*exp[1..-1]) if exp[0] == :do 
    return compile_defun(*exp[1..-1]) if (exp[0] == :defun)
    return compile_ifelse(*exp[1..-1]) if (exp[0] == :if)
    return compile_lambda(*exp[1..-1]) if (exp[0] == :lambda)
    return compile_call(exp[1],exp[2]) if (exp[0] == :call)
    return compile_call(exp[0],exp[1..-1])
  end

  def compile_main(exp)
    # Taken from gcc -S output
    puts <<PROLOG
	.text
.globl main
	.type	main, @function
main:
	leal	4(%esp), %ecx
	andl	$-16, %esp
	pushl	-4(%ecx)
	pushl	%ebp
	movl	%esp, %ebp
	pushl	%ecx
PROLOG

    compile_exp(exp)

    puts <<EPILOG
	popl	%ecx
	popl	%ebp
	leal	-4(%ecx), %esp
	ret

EPILOG

    output_functions
    output_constants
  end

  def compile(exp) 
    compile_main([:do, DO_BEFORE, exp, DO_AFTER]) 
  end  
end

prog = [:do,
  [:call, [:lambda, [], [:puts, "Test"]], [] ]
]

Compiler.new.compile(prog)
