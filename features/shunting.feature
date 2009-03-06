
Feature: Shunting Yard
	In order to parse expressions, the compiler uses a parser component that uses the shunting yard 
	algorithm to parse expressions based on a table.

	Scenario Outline: Basic expressions
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr        | tree                                           |
	  | "1 + 2"     | [:add,1,2]                                     |
	  | "1 - 2"     | [:sub,1,2]									 |
      | "1 + 2 * 3" | [:add,1,[:mul,2,3]]                            |
	  | "1 * 2 + 3" | [:add,[:mul,1,2],3]							 |

	Scenario Outline: Terminating expressions with keywords
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>
		And the remainder of the scanner stream should be <remainder>

	Examples:
	  | expr        | tree                     | remainder                   |
      | "1 + 2 end" | [:add,1,2]               | "end"                       |
      | "1 + 2 if"  | [:add,1,2]               | "if"                        |


