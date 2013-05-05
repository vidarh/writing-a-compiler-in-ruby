

Feature: Tokenizers
    In order to tokenize programs, a series of tokenizer classes provides
    components that can tokenize various subsets of Ruby tokens.

    @operators
    Scenario Outline: Operators
        Given the expression <expr>
        When I tokenize it with the Oper tokenizer
        Then the result should be <result>

    Examples:
      | expr                   | result   |
      | "="                    | :"="     |
      | "=="                   | :"=="    |
      | "&"                    | :"&"     |
      | "&&"                   | :"&&"    |
      | "+"                    | :"+"     |
      | "+="                   | :"+="    |