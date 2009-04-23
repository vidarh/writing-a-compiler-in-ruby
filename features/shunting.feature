
Feature: Shunting Yard
	In order to parse expressions, the compiler uses a parser component that uses the shunting yard 
	algorithm to parse expressions based on a table.

	Scenario Outline: Basic expressions
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                 | tree                                 |
      | "__FILE__"           | :__FILE__                            |
	  | "1 + 2"              | [:add,1,2]                           |
	  | "1 - 2"              | [:sub,1,2]				            |
      | "1 + 2 * 3"          | [:add,1,[:mul,2,3]]                  |
	  | "1 * 2 + 3"          | [:add,[:mul,1,2],3]		   	        |
	  | "(1+2)*3"            | [:mul,[:add,1,2],3]                  |
	  | "1 , 2"              | [:comma,1,2]                         |
	  | "a << b"             | [:shiftleft,:a,:b]                   |
	  | "1 .. 2"             | [:range,1,2]	                        |
      | "a = 1 or foo + bar" | [:or,[:assign,:a,1],[:add,:foo,:bar]]|
      | "foo and !bar"       | [:and,:foo,[:not,:bar]]              |
      | "return 1"           | [:return,1]                          |
      | "return"             | [:return]                            |
      | "5"                  | 5                                    |
      | "?A"                 | 65                                   |
      | "foo +\nbar"         | [:add,:foo,:bar]                     |
      | ":sym"               | :":sym"                              |
      | ":[]"                | :":[]"                               |

	Scenario Outline: Method calls
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                 | tree                                     |
	  | "foo(1)"             | [:call,:foo,1]                           |
	  | "foo(1,2)"           | [:call,:foo,[1,2]]                       |
	  | "foo 1"              | [:call,:foo,1]                           |
	  | "foo 1,2"            | [:call,:foo,[1,2]]                       |
	  | "self.foo"           | [:callm,:self,:foo]                      |
	  | "self.foo(1)"        | [:callm,:self,:foo,1]                    |
	  | "self.foo(1,2)"      | [:callm,:self,:foo,[1,2]]                |
	  | "self.foo bar"       | [:callm,:self,:foo,:bar]                 |
      | "foo(*arg)"          | [:call,:foo,[:splat, :arg]]              |
      | "foo(*arg,bar)"      | [:call,:foo,[[:splat, :arg],:bar]]       |
      | "foo(1 + arg)"       | [:call,:foo,[:add, 1, :arg]]             |
      | "foo(1 * arg,bar)"   | [:call,:foo,[[:mul, 1, :arg],:bar]]      |
      | "ret.flatten.uniq"   | [:callm,[:callm,:ret,:flatten],:uniq]    |

	Scenario Outline: Array syntax
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr        | tree                                     |
      | "[]"        | [:array]                                 |
      | "[1,2]"     | [:array,1,2]                             |
      | "[1,2] + [3]"| [:add,[:array,1,2],[:array,3]]          |
      | "[1,[2,3]]" | [:array,1,[:array,2,3]]                  |
      | "a = [1,2]" | [:assign,:a,[:array,1,2]]                |
      | "a = []"    | [:assign,:a,[:array]]                    |
	  | "[o.sym]"   | [:array,[:callm,:o,:sym]]                | 
	  | "[o.sym(1)]"   | [:array,[:callm,:o,:sym,1]]           | 
	  | "[o.sym,foo]"| [:array,[:callm,:o,:sym],:foo]          | 
	  | "[1].compact"| [:callm,[:array,1],:compact]            | 
	  | "return []"  | [:return,[:array]]                      |

    @arrays
	Scenario Outline: Array operators
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr         | tree                                  | notes |
	  | "a[1]"       | [:callm,:a,:[],[1]]                   |       |
      | "Set[1,2,3]" | [:callm,:Set,:[],[1,2,3]]             |       |
      | "r[2][0]"    | [:callm, [:callm,:r,:[],[2]],:[],[0]] |       |
      | "s.foo[0]"   | [:callm, [:callm,:s,:foo],:[],[0]]    |       |
      | "foo[1] = 2" | [:callm, :foo, :[]=, [1m2]]           | Tree rewrite |

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


	Scenario Outline: Handling variable arity expressions
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr            | tree                                      |
	  | "return 1"      | [:return,1]                               |
	  | "return"        | [:return]                                 |
	  | "5 or return 1" | [:or,5,[:return,1]]                       |
	  | "5 or return"   | [:or,5,[:return]]                         |
	  | "return if 5"   | [:return]                                 |

	Scenario Outline: Complex expressions
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr              | tree                                    |
      | "foo ? 1 : 0"     | [:ternif, :foo, [:ternalt, 1, 0]]       |
      | "(rest? ? 1 : 0)" | [:ternif, :rest?, [:ternalt, 1, 0]]     |
      | "@locals[a] + (rest? ? 1 : 0)" | [:add, [:callm, :@locals,:[], [:a]], [:ternif, :rest?, [:ternalt, 1, 0]]] |

	Scenario Outline: Blocks
		Given the expression <expr>
		When I parse it with the shunting yard parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                | tree                                       |
	  | "foo do end"        | [:call, :foo, [], [:block]]                |
      | "foo.bar do end"    | [:callm, :foo, :bar, [], [:block]]         |
	  | "foo {}"            | [:call, :foo, [],[:block]]                 |
      | "foo() {}"          | [:call, :foo, [],[:block]]                 |
      | "foo(1) {}"         | [:call, :foo, 1,[:block]]                  |
	  | "foo 1 {}"	        | [:call, :foo, 1,[:block]]                  |
      | "foo(1,2) {}"       | [:call, :foo, [1,2],[:block]]              |
	  | "foo = bar {}"	    | [:assign, :foo, [:call, :bar, [],[:block]]]|
      | "&foo"              | [:to_block, :foo]                          |
