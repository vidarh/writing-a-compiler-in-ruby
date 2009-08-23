
Feature: Compiler
	The compiler class turns the parse tree into a stream of assembler
	instructions

	Scenario Outline: Simple programs
		Given the expression <expr>
		When I compile it
		Then the output should be <asm>

	Examples:
	 | expr           | asm |
     | "1"            | [[:movl, 1, :eax], [".section", ".rodata"], [".section", ".bss"]] |
     | "foo = 1 "     | [[:movl, 1, "foo"], [".section", ".rodata"], [".section", ".bss"], ["foo"], [".long 0"]] |
	 | "def foo; 1; end" | [[:movl, "$foo", :eax], [:export, "foo", :function], ["foo"], [:pushl, :ebp], [:movl, :esp, :ebp], [:subl, 4, :esp], [:movl, 1, :eax], [:addl, 4, :esp], [:leave], [:ret], [".size", "foo", ".-foo"], [".section", ".rodata"], [".section", ".bss"]] |
 
	Scenario Outline: Running programs
		Given the source file <infile>
		When I compile it and run it
		Then the output should match <outfile>

	Examples:
	| infile                    | outfile                | notes |
	| inputs/01trivial.rb       | outputs/01trivial.txt  | Just a puts |
    | inputs/02class.rb         | outputs/02class.txt    | Simple class |
    | inputs/03ivar.rb          | outputs/03ivar.txt     | Setting and retrieving an instance variable |
    | inputs/05cvar.rb          | outputs/05cvar.txt     | Simple use of class variable |
    | inputs/symbol_to_s.rb     | outputs/symbol_to_s.txt | :hello.to_s |
    | inputs/new_with_arg.txt   | outputs/new_with_arg.txt | Foo.new(some arg) |
    | inputs/string_to_sym.rb   | outputs/string_to_sym.txt| "foo".to_sym.to_s |
    | inputs/04accessor.rb      | outputs/04accessor.txt | Simple use of attr_accessor |

		