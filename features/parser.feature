
Feature: Parser
	In order to parse programs, the compiler uses a collection of 
	parser components that are combined together to form the full
	parser.

	Scenario Outline: Simple expressions
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                 | tree                                          | notes                                              |
	  | "1 + 2"              | [:do,[:add,1,2]]                              | The full parser wraps a [:do] around everything    |
	  | "foo { }"            | [:do,[:call,:foo,[], [:block]]]               | Testing empty blocks                               |
	  | "foo(1) { }"         | [:do,[:call,:foo,1, [:block]]]                | Testing empty blocks                               |
	  | "foo(1) { bar }"     | [:do,[:call,:foo,1, [:block, [],[:bar]]]]     | Testing function calls inside a block              |
	  | "foo(1) { bar 1 }"   | [:do,[:call,:foo,1, [:block, [],[[:call,:bar,1]]]]] | Testing function calls inside a block          |
	  | "foo { bar[0] }"     | [:do,[:call,:foo,[],[:block, [],[[:index,:bar,0]]]]]| Testing index operator inside a block          |
