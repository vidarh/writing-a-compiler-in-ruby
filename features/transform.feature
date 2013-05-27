
Feature: Transformations
  In order to implement the correct semantics, the compiler post-processes
  the output from the Parser to modify the AST.

  Scenario Outline: Simple expressions
    Given the expression <expr>
    When I parse it with the full parser
    And I preprocess it with the compiler transformations
    Then the parse tree should become <tree>

    Examples:
    | expr    | tree                                                                               | notes |
    | "1 + 2" | [:do,[:add, [:sexp,[:call, :__get_fixnum, 1]], [:sexp,[:call, :__get_fixnum, 2]]]] |       |


