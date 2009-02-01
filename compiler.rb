#!/bin/env ruby

# Step 2

class Compiler
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
    
    puts "\tsubl\t$4,%esp"

    args.each do |a|
      puts "\tmovl\t$.LC#{a},(%esp)"
    end

    puts "\tcall\t#{call}"
	puts "\taddl\t$4, %esp"
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

prog = [:puts,"Hello World"]

Compiler.new.compile(prog)
