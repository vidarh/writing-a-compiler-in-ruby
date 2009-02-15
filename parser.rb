require 'sexp'

class Parser
  include Tokens

  def initialize s
    @s = s
    @sexp = SEXParser.new(s)
  end

  def parse_sexp 
    @sexp.parse
  end

  def parse
    res = [:do]
    @s.ws
    while e = parse_sexp
      res << e
      @s.ws
    end
    return res
  end
end
