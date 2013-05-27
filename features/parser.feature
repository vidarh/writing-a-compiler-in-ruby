
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
	  | expr                            | tree                                                 | notes                                              |
	  | "1 + 2"                         | [:do,[:add,1,2]]                                     | The full parser wraps a [:do] around everything    |
	  | "foo { }"                       | [:do,[:call,:foo,[], [:lambda]]]                      | Testing empty blocks                               |
	  | "foo(1) { }"                    | [:do,[:call,:foo,1, [:lambda]]]                       | Testing empty blocks                               |
	  | "foo(1) { bar }"                | [:do,[:call,:foo,1, [:lambda, [],[:bar]]]]            | Testing function calls inside a block              |
	  | "foo(1) { bar 1 }"              | [:do,[:call,:foo,1, [:lambda, [],[[:call,:bar,1]]]]]  | Testing function calls inside a block              |
	  | "foo { bar[0] }"                | [:do,[:call,:foo,[],[:lambda, [],[[:callm,:bar,:[],[0]]]]]]| Testing index operator inside a block         |
	  | "while foo do end"              | [:do, [:while, :foo, [:do]]]                         | while with "do ... end" instead of just "end"      |
      | "Keywords=Set[1]"+10.chr+"foo"          | [:do,[:assign,:Keywords,[:callm,:Set,:[],[1]]],:foo] | :rp before linefeed should terminate an expression |
	  | "expect(',') or return args"    | [:do,[:or,[:call,:expect,","],[:return,:args]]]      | Priority of "or" vs. call/return                   |
      | "require File.dirname() + '/../spec_helper'" | [:do, [:require, [:add, [:callm, :File, :dirname, nil], "/../spec_helper"]]]  |              |
      | "File.dirname() + '/../spec_helper'" | [:do, [:add, [:callm, :File, :dirname, nil], "/../spec_helper"]] |                                   |
      | "dirname() + '/../spec_helper'" | [:do, [:add,[:call, :dirname],"/../spec_helper"]]    | |
      | "return rest? ? foo : bar"      | [:do, [:return, [:ternif, :rest?, [:ternalt, :foo, :bar]]]] | |

    @hash
    Scenario Outline: Hash syntax
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

    Examples:
	  | expr                 | tree                                          | notes                                              |
      | "{}"                 | [:do,[:hash]]                                 | Literal hash                                       |
      | "{:a => 1}"          | [:do,[:hash,[:pair,:":a",1]]]                 | Literal hash                                       |
      | "{:a => 1"+10.chr+"}"        | [:do,[:hash,[:pair,:":a",1]]]                 | Literal hash with linefeed                         |
      | "{:a => 1,}"         | [:do,[:hash,[:pair,:":a",1]]]                 | Literal hash with trailing comma                   |
      | "{:a => 1, :b => 2}" | [:do,[:hash,[:pair,:":a",1],[:pair,:":b",2]]] | Literal hash with two values                       |
      | "vtable = {}"        | [:do,[:assign,:vtable,[:hash]]]               | Literal hash                                       |
      | "foo = {:a => 1,}"   | [:do,[:assign,:foo,[:hash,[:pair,:":a",1]]]]  | Literal hash with trailing comma                   |
      | "{:a => foo(1), :b => foo(2)}" |  [:do, [:hash, [:pair, :":a", [:call, :foo, 1]], [:pair, :":b", [:call, :foo, 2]]]] | Hash where value is a function call | 


	@interpol
	Scenario Outline: String interpolation
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                 | tree                                          | notes                                              |
	  | '"#{1}"'             | [:do,[:concat,"",1]]                          | Basic case                                         |
      | '"#{""}"'            | [:do,[:concat,"",""]]                         | Interpolated expression containing a string        |
      | '"Parsing #{"Ruby #{"is #{ %(hard)}"}"}."' |  [:do, [:concat, "Parsing ", [:concat, "Ruby ", [:concat, "is ", "hard"]], "."]] | Courtesy of http://www.jbarnette.com/2009/01/22/parsing-ruby-is-hard.html |


        @funcdef
	Scenario Outline: Function definition
		Given the expression <expr>
        When I parse it with the full parser
        Then the parse tree should become <tree>

    Examples:
	  | expr                          | tree                                          | notes                                         |
	  | "def foo(bar=nil); end"     | [:do, [:defm, :foo, [:bar], []]]    | Default value for arguments                   |
	  | "def foo(bar = nil); end"   | [:do, [:defm, :foo, [:bar], []]]     | Default value for arguments - with whitespace |
	  | "def foo(bar = []); end"    | [:do, [:defm, :foo, [:bar], []]]     | Default value for arguments - with whitespace |
	  | "def foo(&bar);end  "      | [:do, [:defm, :foo, [[:bar,:block]], []]] | Block as named argument                  |
	  | "def foo(a = :b, c = :d);end;  " | [:do, [:defm, :foo, [:a,:c], []]] | Second argument following argument with initializer |
	  | "def foo(a = :b, &bar);end;  " | [:do, [:defm, :foo, [:a,[:bar,:block]], []]] | Second argument following argument with initializer |
	  | "def self.foo;end;"         | [:do, [:defm, [:self,:foo], [], []]] | Class method etc.                             |
	  | "def *(other_array); end;"         | [:do, [:defm, :*, [:other_array], []]] | *-Operator overloading                |
	  | "def foo=(bar);end;"         | [:do, [:defm, :foo=, [:bar], []]] | setter    	       		                  |
          | "def == bar; end"             | [:do, [:defm, :==, [:bar], []]]              | Handle operator method name            |

    @class
    Scenario Outline: Classes
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                          | tree                                          | notes                                         |
      | "class Foo; end"              | [:do, [:class, :Foo, :Object, []]]            |                                               |
      | "class Foo < Bar; end"        | [:do, [:class, :Foo, :Bar, []]]               |                                               |

    @control
	Scenario Outline: Control structures
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
	  | expr                          | tree                                          | notes                                         |
	  | "case foo; when a; end"       | [:do, [:case, :foo, [[:when, :a, []]]]]       | Basic case structure                          |
      | "case foo; when a; b;when c; d; end" | [:do,[:case, :foo, [[:when,:a,[:b]],[:when,:c,[:d]]]]] | More complicated case         |
      | "case foo; when ?a..?z, ?A..?Z; end" | [:do, [:case, :foo, [[:when, [[:range, 97, 122], [:range, 65, 90]], []]]]] | "When" with multiple conditions |
      | "begin; puts 'foo';rescue Exception => e; end; " |  [:do, [:block, [], [[:call, :puts, "foo"]], [:rescue, :Exception, :e, []]]] | begin/rescue |
      | "unless foo; bar; else; baz; end" | [:do, [:unless, :foo, [:do, :bar], [:do, :baz]]] | |



    @operatorcalls
    Scenario Outline: Operator method calls
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
      | expr     | tree                      | notes |
      | "1.+(2)" | [:do, [:callm, 1, :+, 2]] |       |

