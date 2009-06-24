
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

