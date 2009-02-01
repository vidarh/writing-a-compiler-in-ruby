#!/bin/env ruby

# Step 2

class Compiler
  PTR_SIZE=4

  def initialize
    @string_constants = {}
    @seq = 0
  end

  def get_arg(a)
    # For now we assume strings only
    seq = @string_constants[a]
    return seq if seq
    seq = @seq
    @seq += 1
    @string_constants[a] = seq
    return seq
  end

  def output_constants
    puts "\t.section\t.rodata"
    @string_constants.each do |c,seq|
      puts ".LC#{seq}:"
      puts "\t.string \"#{c}\""
    end
  end

  def compile_exp(exp)
    call = exp[0].to_s

    args = exp[1..-1].collect {|a| get_arg(a)}

    # gcc on i386 does 4 bytes regardless of arguments, and then
    # jumps up 16 at a time. We will blindly do the same.
    stack_adjustment = PTR_SIZE + (((args.length+0.5)*PTR_SIZE/(4.0*PTR_SIZE)).round) * (4*PTR_SIZE)
    puts "\tsubl\t$#{stack_adjustment}, %esp"
    args.each_with_index do |a,i|
      puts "\tmovl\t$.LC#{a},#{i>0 ? i*PTR_SIZE : ""}(%esp)"
    end

    puts "\tcall\t#{call}"
    puts "\taddl\t$#{stack_adjustment}, %esp"
  end

  def compile(exp)
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

    output_constants

  end
end

prog = [:printf,"Hello %s\\n","World"]

Compiler.new.compile(prog)
