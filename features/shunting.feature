
Feature: Shunting Yard
	In order to parse expressions, the compiler uses a parser component that uses the shunting yard 
	algorithm to parse expressions based on a table.

	Scenario Outline: Basic expressions
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                 | tree                                 |
	  | "1 + 2"              | [:add,1,2]                           |
	  | "1 - 2"              | [:sub,1,2]				            |
      | "1 + 2 * 3"          | [:add,1,[:mul,2,3]]                  |
	  | "1 * 2 + 3"          | [:add,[:mul,1,2],3]		   	        |
	  | "(1+2)*3"            | [:mul,[:add,1,2],3]                  |
	  | "1 , 2"              | [:comma,1,2]                         |
	  | "a << b"             | [:shiftleft,:a,:b]                   |
	  | "a = 1 or foo + bar" | [:or,[:assign,:a,1],[:add,:foo,:bar]]|
      | "return 1"           | [:return,1]                          |
      | "return"             | [:return]                            |

	Scenario Outline: Method calls
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr           | tree                                     |
	  | "foo(1)"       | [:call,:foo,1]                           |
	  | "foo(1,2)"     | [:call,:foo,[1,2]]                       |
	  | "foo 1"        | [:call,:foo,1]                           |
	  | "foo 1,2"      | [:call,:foo,[1,2]]                       |
	  | "self.foo"     | [:callm,:self,:foo]                      |
	  | "self.foo(1)"  | [:callm,:self,:foo,1]                    |
	  | "self.foo(1,2)"| [:callm,:self,:foo,[1,2]]                |
	  | "self.foo bar" | [:callm,:self,:foo,:bar]                 |

	Scenario Outline: Array syntax
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr        | tree                                           |
      | "[]"        | [:createarray]                                 |
      | "[1,2]"     | [:createarray,1,2]                             |
      | "a = [1,2]" | [:assign,:a,[:createarray,1,2]]                |
      | "a = []"    | [:assign,:a,[:createarray]]                    |

	Scenario Outline: Array operators
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr        | tree                                           |
	  | "a[1]"      | [:index,:a,1]                                  |

    Scenario Outline: Function calls
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                       | tree                                         |
	  | "attr_reader :args,:body"  | [:call, :attr_reader, [:":args", :":body"]]  |

	Scenario Outline: Terminating expressions with keywords
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>
		And the remainder of the scanner stream should be <remainder>

	Examples:
	  | expr        | tree                     | remainder                   |
      | "1 + 2 end" | [:add,1,2]               | "end"                       |
      | "1 + 2 if"  | [:add,1,2]               | "if"                        |


