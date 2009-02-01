#!/bin/env ruby

DO_BEFORE= [:do,
  [:defun, :hello_world,[], [:puts, "Hello World"]]
]

DO_AFTER= []


class Compiler
  PTR_SIZE=4

  def initialize
    @string_constants = {}
    @global_functions = {}
    @seq = 0
  end

  def get_arg(a)
    # Handle strings or subexpressions 
    if a.is_a?(Array) 
      compile_exp(a) 
      return [:subexpr] 
     end 

    seq = @string_constants[a]
    return seq if seq
    seq = @seq
    @seq += 1
    @string_constants[a] = seq
    return [:strconst,seq]
  end

  def output_constants
    puts "\t.section\t.rodata"
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

  def defun name, args, body
    @global_functions[name] = [args,body]
  end

  def compile_exp(exp)
    return if !exp || exp.size == 0

    if exp[0] == :do 
      exp[1..-1].each { |e| compile_exp(e) } 
      return 
    end 

    return defun(*exp[1..-1]) if (exp[0] == :defun)

    call = exp[0].to_s

    stack_adjustment = PTR_SIZE + (((exp.length-1+0.5)*PTR_SIZE/(4.0*PTR_SIZE)).round) * (4*PTR_SIZE)

    puts "\tsubl\t$#{stack_adjustment}, %esp" if exp[0] != :do
    
    exp[1..-1].each_with_index do |a,i| 
      atype, aparam = get_arg(a)
      if exp[0] != :do
        if atype == :strconst
          param = "$.LC#{aparam}"
        else
          param = "%eax"
        end
        puts "\tmovl\t#{param},#{i>0 ? i*4 : ""}(%esp)"
      end
    end

    puts "\tcall\t#{call}"
    puts "\taddl\t$#{stack_adjustment}, %esp"
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
	.size	main, .-main
EPILOG

    output_functions
    output_constants
  end

  def compile(exp) 
    compile_main([:do, DO_BEFORE, exp, DO_AFTER]) 
  end  
end

prog = [:hello_world]

Compiler.new.compile(prog)
