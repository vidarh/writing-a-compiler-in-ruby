
Feature: Parser
	In order to parse programs, the compiler uses a collection of 
	parser components that are combined together to form the full
	parser.

    @parserexp
	Scenario Outline: Simple expressions
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
      | expr                                         | tree                                                                       | notes                                              |
      | "% x "                                       | [:do,"x"]                                                                  | The full parser wraps a [:do] around everything    |
      | "a + % x "                                   | [:do,[:+,:a,"x"]]                                                          | The full parser wraps a [:do] around everything    |
      | "1 % 2 "                                     | [:do,[:%,1,2]]                                                             | The full parser wraps a [:do] around everything    |
      | "1 % 2"                                      | [:do,[:%,1,2]]                                                             | The full parser wraps a [:do] around everything    |

