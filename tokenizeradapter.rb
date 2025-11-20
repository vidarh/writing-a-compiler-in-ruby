
# The purpose of this class is to serve as an adapter between the
# ShuntingYard component, the Tokenizer, and the Parser.
# The reason for this is that a number of tokens indicate 
# a need to call back into the parser, but the ShuntingYard
# class only need to know that what is returned is not an operator
# it should be concerned about

class TokenizerAdapter

  def initialize(tokenizer, parser)
    @tokenizer = tokenizer
    @parser    = parser

    @escape_tokens = {
      :stabby_lambda => :parse_stabby_lambda,
      :case => :parse_case
    }
  end

  def each
    @tokenizer.each do |token, op, keyword|
      if keyword and (m = @escape_tokens[token])
        @tokenizer.unget(token)
        ss = @parser.send(m)
        yield(ss, nil, nil)
      else
        yield(token,op,keyword)
      end
    end
  end

  def get_quoted_exp(unget=:unget)
    @tokenizer.get_quoted_exp(unget)
  end

  def ws
    @tokenizer.ws
  end

  def nolfws
    @tokenizer.nolfws
  end

  def unget token
    @tokenizer.unget(token)
  end

  def lasttoken
    @tokenizer.lasttoken
  end

  def newline_before_current
    @tokenizer.newline_before_current
  end

  def scanner
    @tokenizer.scanner
  end
end
