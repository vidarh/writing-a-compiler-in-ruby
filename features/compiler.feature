
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
		Then the output should match <outfile>

	Examples:
    | infile                  | outfile                   | notes                                              |
    | inputs/01trivial.rb     | outputs/01trivial.txt     | Just a puts                                        |
    | inputs/01btrivial.rb    | outputs/01btrivial.txt    | Method call with single numeric argument.          |
    | inputs/01ctrivial.rb    | outputs/01ctrivial.txt    | A puts with no argument                            |
    | inputs/02class.rb       | outputs/02class.txt       | Simple class                                       |
    | inputs/method.rb        | outputs/method.txt        | Class w/method with single argument                |
    | inputs/method2.rb       | outputs/method2.txt       | Class w/method with non-initialize method w/2 args |
    | inputs/method3.rb       | outputs/method3.txt       | Class w/method with two arguments                  |
    | inputs/03ivar.rb        | outputs/03ivar.txt        | Setting and retrieving an instance variable        |
    | inputs/05cvar.rb        | outputs/05cvar.txt        | Simple use of class variable                       |
    | inputs/symbol_to_s.rb   | outputs/symbol_to_s.txt   | :hello.to_s                                        |
    | inputs/new_with_arg.txt | outputs/new_with_arg.txt  | Foo.new(some arg)                                  |
    | inputs/string_to_sym.rb | outputs/string_to_sym.txt | "foo".to_sym.to_s                                  |
    | inputs/04accessor.rb    | outputs/04accessor.txt    | Simple use of attr_accessor                        |
    | inputs/06print.rb       | outputs/06print.txt       | Basic print/puts support                           |
    | inputs/interpolate.rb   | outputs/interpolate.txt   | Simple string interpolation                        |
    | inputs/div.rb           | outputs/div.txt           | Repeated divs to check register alloc.             |
    | inputs/stdout.rb        | outputs/stdout.txt        | Test basic STDOUT                                  |
    | inputs/stdin.rb         | outputs/stdin.txt         | Test basic STDIN                                   |
    | inputs/ivar.rb          | outputs/ivar.txt          | Test instance vars in subclasses                   |


    @logic
	Scenario Outline: Running programs
		Given the source file <infile>
		When I compile it and run it
		Then the output should match <outfile>

	Examples:
    | infile                 | outfile                  | notes                                          |             |
    | inputs/shortcircuit.rb | outputs/shortcircuit.txt | Test that "&&" actuall shortcircuits execution | Just a puts |
