
Feature: Compiler
	The compiler class turns the parse tree into a stream of assembler
	instructions

	Scenario Outline: Simple programs
		Given the expression <expr>
		When I compile it
		Then the output should be <asm>

	Examples:
	 | expr           | asm |
#     | "1"            | [[:movl, 1, :eax], [".section", ".rodata"], [".section", ".bss"]] |
#     | "foo = 1 "     | [[:movl, 1, "foo"], [".section", ".rodata"], [".section", ".bss"], ["foo"], [".long 0"]] |
#	 | "def foo; 1; end" | [[:movl, "$foo", :eax], [:export, "foo", :function], ["foo"], [:pushl, :ebp], [:movl, :esp, :ebp], [:subl, 4, :esp], [:movl, 1, :eax], [:addl, 4, :esp], [:leave], [:ret], [".size", "foo", ".-foo"], [".section", ".rodata"], [".section", ".bss"]] |
 
	Scenario Outline: Running programs
		Given the source file <infile>
		When I compile it and run it
		Then the output should match the outputs/* file

	Examples:
    | infile           | notes                                              |
    | 01trivial.rb     | Just a puts                                        |
    | 01btrivial.rb    | Method call with single numeric argument.          |
    | 01ctrivial.rb    | A puts with no argument                            |
    | 02class.rb       | Simple class                                       |
    | method.rb        | Class w/method with single argument                |
    | method2.rb       | Class w/method with non-initialize method w/2 args |
    | method3.rb       | Class w/method with two arguments                  |
    | 03ivar.rb        | Setting and retrieving an instance variable        |
    | 05cvar.rb        | Simple use of class variable                       |
    | symbol_to_s.rb   | :hello.to_s                                        |
    | new_with_arg.txt | Foo.new(some arg)                                  |
    | string_to_sym.rb | "foo".to_sym.to_s                                  |
    | 04accessor.rb    | use of attr_accessor                               |
    | 06print.rb       | print/puts support                                 |
    | interpolate.rb   | string interpolation                               |
    | div.rb           | Repeated divs to check register alloc.             |
    | stdout.rb        | Test basic STDOUT                                  |
    | stdin.rb         | Test basic STDIN                                   |
    | ivar.rb          | Test instance vars in subclasses                   |
    | methodnames.rb   | foo= is a valid method name, and distinct from foo |
    | classname.rb     | Class#name                                         |
    | strcmp.rb        | Basic String#== tests                              |
    | defaultargs.rb   | Default arguments to methods                       |
    | nil.rb           | Basic checks of "nil"                              |
    | typed_and.rb     | Regression check for and/or with typing            |
    | redefine.rb      | Re-opening classes                                 |

    @logic
	Scenario Outline: Running programs
		Given the source file <infile>
		When I compile it and run it
		Then the output should match the outputs/* file

	Examples:
    | infile          | notes                                          |
    | shortcircuit.rb | Test that "&&" actuall shortcircuits execution |
