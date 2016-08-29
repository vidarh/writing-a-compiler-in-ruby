
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
      | "1 + 2"                                      | [:do,[:+,1,2]]                                                             | The full parser wraps a [:do] around everything    |
      | "1 * 2"                                      | [:do,[:*,1,2]]                                                             | |
      | "foo(1)"                                     | [:do,[:call,:foo,[1]]]                                                     | Simple function/method call                        |
      | "foo(1*2)"                                   | [:do,[:call,:foo,[[:*,1,2]]]]                                              | Simple function/method call                        |
      | "foo(1*a)"                                   | [:do,[:call,:foo,[[:*,1,:a]]]]                                             | Simple function/method call                        |
      | "foo(@a*1)"                                  | [:do,[:call,:foo,[[:*,:"@a",1]]]]                                          | Simple function/method call                        |
      | "foo(1,2)"                                   | [:do,[:call,:foo,[1,2]]]                                                   | Simple function/method call                        |
      | "foo { }"                                    | [:do,[:call,:foo,[], [:proc]]]                                             | Testing empty blocks                               |
      | "foo(1) { }"                                 | [:do,[:call,:foo,1, [:proc]]]                                              | Testing empty blocks                               |
      | "@s.expect(Quoted) { }"    | [:do, [:callm, :@s, :expect, :Quoted, [:proc]]]  | |
      | "foo(1) { bar }"                             | [:do,[:call,:foo,1, [:proc, [],[:bar]]]]                                  | Testing function calls inside a block              |
      | "foo(1) { bar 1 }"                           | [:do,[:call,:foo,1, [:proc, [],[[:call,:bar,[1]]]]]]                      | Testing function calls inside a block              |
      | "foo { bar[0] }"                             | [:do,[:call,:foo,[],[:proc, [],[[:callm,:bar,:[],[0]]]]]]                 | Testing index operator inside a block              |
      | "while foo do end"                           | [:do, [:while, :foo, [:do]]]                                               | while with "do ... end" instead of just "end"      |
      | "Keywords=Set[1]"+10.chr+"foo"               | [:do,[:assign,:Keywords,[:callm,:Set,:[],[1]]],:foo]                       | :rp before linefeed should terminate an expression |
      | "expect(',') or return args"                 | [:do,[:or,[:call,:expect,[","]],[:return,:args]]]                          | Priority of "or" vs. call/return                   |
      | "require File.dirname() + '/../spec_helper'" | [:do, [:require, [:+, [:callm, :File, :dirname], "/../spec_helper"]]]      |                                                    |
      | "File.dirname() + '/../spec_helper'"         | [:do, [:+, [:callm, :File, :dirname], "/../spec_helper"]]                  |                                                    |
      | "dirname() + '/../spec_helper'"              | [:do, [:+,[:call, :dirname],"/../spec_helper"]]                            |                                                    |
      | "return rest? ? foo : bar"                   | [:do, [:return, [:ternif, :rest?, [:ternalt, :foo, :bar]]]]                |                                                    |
      | "-1"                                         | [:do, -1]                                                                  | Negative number                                    |
      | "-a"                                         | [:do, [:-, :a]]                                                            | Unary minus                                        |
      | "b-a"                                        | [:do, [:-, :b, :a]]                                                        | Infix minus                                        |
      | ":a"                                         | [:do, :":a"]                                                               |                                                    |
      | ":-"                                         | [:do, :":-"]                                                               |                                                    |
      | ":<"                                         | [:do, :":<"]                                                               |                                                    |
      | ":/"                                         | [:do, :":/"]                                                               |                                                    |

    @quotes
    Scenario Outline: Quotes
      Given the expression <expr>
      When I parse it with the full parser
      Then the parse tree should become <tree>
      
    Examples:
      | expr      | tree  | notes         |
      | "%w{1 2}" | [:do, [:array, "1","2"]] | Quoting Words |

    @hash
    Scenario Outline: Hash syntax
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

    Examples:
      | expr                           | tree                                                                               | notes                               |
      | "{}"                           | [:do,[:hash]]                                                                      | Literal hash                        |
      | "{:a => 1}"                    | [:do,[:hash,[:pair,:":a",1]]]                                                      | Literal hash                        |
      | "{:a => 1"+10.chr+"}"          | [:do,[:hash,[:pair,:":a",1]]]                                                      | Literal hash with linefeed          |
      | "{:a => 1,}"                   | [:do,[:hash,[:pair,:":a",1]]]                                                      | Literal hash with trailing comma    |
      | "{:a => 1, :b => 2}"           | [:do,[:hash,[:pair,:":a",1],[:pair,:":b",2]]]                                      | Literal hash with two values        |
      | "vtable = {}"                  | [:do,[:assign,:vtable,[:hash]]]                                                    | Literal hash                        |
      | "foo = {:a => 1,}"             | [:do,[:assign,:foo,[:hash,[:pair,:":a",1]]]]                                       | Literal hash with trailing comma    |
      | "{:a => foo(1), :b => foo(2)}" | [:do, [:hash, [:pair, :":a", [:call, :foo, [1]]], [:pair, :":b", [:call, :foo, [2]]]]] | Hash where value is a function call |
      | "{:a => 1, }"                  | [:do, [:hash, [:pair,:":a",1]]]                                                    | Trailing ,                          |
      | "a = {'foo' => :bar}"          | [:do, [:assign, :a, [:hash, [:pair, "foo", :":bar"]]]]                             |                                     |


    @comments
    Scenario Outline: Comments
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

    Examples:
      | expr                                         | tree             | notes                 |
      | '#comment'                                   | [:do]            | Basic comment         |
      | '#comment'+10.chr+'5 + 2'+10.chr+'#and more' | [:do,[:+,5 , 2]] | Sandwiched expression |
      | '# ";"'                                      | [:do]            | "Weird" comments      |
      
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
      | expr                             | tree                                                                   | notes                                               |
      | "def foo(bar=nil); end"          | [:do, [:defm, :foo, [[:bar, :default, :nil]], []]]                     | Default value for arguments                         |
      | "def foo(bar = nil); end"        | [:do, [:defm, :foo, [[:bar, :default, :nil]], []]]                     | Default value for arguments - with whitespace       |
      | "def foo(bar = []); end"         | [:do, [:defm, :foo, [[:bar, :default, [:array]]], []]]                 | Default value for arguments - with whitespace       |
      | "def foo(&bar);end  "            | [:do, [:defm, :foo, [[:bar,:block]], []]]                             | Block as named argument                             |
      | "def foo(a = :b, c = :d);end;  " | [:do, [:defm, :foo, [[:a,:default, :":b"],[:c,:default, :":d"]], []]]  | Second argument following argument with initializer |
      | "def foo(a = :b, &bar);end;  "   | [:do, [:defm, :foo, [[:a,:default, :":b"],[:bar,:block]], []]]         | Second argument following argument with initializer |
      | "def self.foo;end;"              | [:do, [:defm, [:self,:foo], [], []]]                                   | Class method etc.                                   |
      | "def *(other_array); end;"       | [:do, [:defm, :*, [:other_array], []]]                                 | *-Operator overloading                              |
      | "def foo=(bar);end;"             | [:do, [:defm, :foo=, [:bar], []]]                                      | setter                                              |
      | "def == bar; end"                | [:do, [:defm, :==, [:bar], []]]                                        | Handle operator method name                         |

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
      | expr                                             | tree                                                                        | notes                           |
      | "case foo; when a; end"                          | [:do, [:case, :foo, [[:when, :a, []]]]]                                     | Basic case structure            |
      | "case foo; when a; b;when c; d; end"             | [:do,[:case, :foo, [[:when,:a,[:b]],[:when,:c,[:d]]]]]                      | More complicated case           |
      | "case foo; when ?a..?z, ?A..?Z; end"             | [:do, [:case, :foo, [[:when, [[:range, 97, 122], [:range, 65, 90]], []]]]]  | "When" with multiple conditions |
      | "begin; puts 'foo';rescue Exception => e; end; " | [:do, [:block, [], [[:call, :puts, ["foo"]]], [:rescue, :Exception, :e, []]]] | begin/rescue                    |
      | "unless foo; bar; else; baz; end"                | [:do, [:unless, :foo, [:do, :bar], [:do, :baz]]]                            |                                 |
      | "if foo; bar; elsif baz; a; else; b; end"        | [:do, [:if, :foo, [:do, :bar], [:do, [:if, :baz, [:do, :a], [:do, :b]]]]]   |                                 |



    @methodcalls
    Scenario Outline: Method calls
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
      | expr                                   | tree                                                                  | notes |
      | "1.+(2)"                               | [:do, [:callm, 1, :+, [2]]]                                           |       |
      | "Position.new(@filename)"              | [:do, [:callm, :Position, :new, [:"@filename"]]]                      |       |
      | "Position.new(@filename,@lineno,@col)" | [:do, [:callm, :Position, :new, [:"@filename", :"@lineno", :"@col"]]] |       |
      | "foo.bar(@a*1)"                              | [:do,[:callm,:foo, :bar,[[:*,:"@a",1]]]]                                   | Simple function/method call                        |


    @logic
    Scenario Outline: Logical operators
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
      | expr                             | tree                                                                    | notes  |
      | "a && b"                         | [:do, [:and, :a, :b]]                                                   | Simple |
      | "!a && b"                        | [:do, [:and, [:!, :a], :b]]                                             | Simple |
      | "false && false ? 'ERROR' : 'OK'" | [:do, [:ternif, [:and, :false, :false], [:ternalt, "ERROR", "OK"]]]     | Operator priorities    |
      | "a = false && false ? 'ERROR' : 'OK'" | [:do, [:assign, :a, [:ternif, [:and, :false, :false], [:ternalt, "ERROR", "OK"]]]] | Operator priorities    |


    @lambda
    Scenario Outline: Lambda and block expressions
      Given the expression <expr>
      When I parse it with the full parser
      Then the parse tree should become <tree>

    Examples:
    | expr                                        | tree                                                                                |
    | "lambda do end"                             | [:do, [:lambda]]                                                                    |
    | "lambda do puts 'test'; end"                | [:do, [:lambda,[], [[:call, :puts, ["test"]]]]]                                     |
    | "lambda do puts 'hello'; puts 'world'; end" | [:do, [:lambda,[], [[:call, :puts, ["hello"]], [:call, :puts, ["world"]]]]]         |
    | "foo    do puts 'hello'; puts 'world'; end" | [:do, [:call, :foo,[], [:proc, [], [[:call, :puts, ["hello"]], [:call, :puts, ["world"]]]]]]  |
    | "l = lambda do puts 'test'; end"            | [:do, [:assign, :l, [:lambda, [], [[:call, :puts, ["test"]]]]]]                     |
    | "l = lambda do puts 'foo'; end; puts 'bar'" | [:do, [:assign, :l, [:lambda, [], [[:call, :puts, ["foo"]]]]], [:call, :puts, ["bar"]]] |
 


    @mod
	Scenario Outline: Simple expressions
		Given the expression <expr>
		When I parse it with the full parser
		Then the parse tree should become <tree>

	Examples:
      | expr       | tree              | notes |
      | "% x "     | [:do,"x"]         |       |
      | "a + % x " | [:do,[:+,:a,"x"]] |       |
      | "1 % 2 "   | [:do,[:%,1,2]]    |       |
      | "1 % 2"    | [:do,[:%,1,2]]    |       |



    


