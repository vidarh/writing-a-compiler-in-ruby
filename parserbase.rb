require 'scanner'
require 'tokens'
require 'pp'

class ParserBase
  include Tokens

  def zero_or_more(sym)
    res = []
    while e = send(("parse_"+sym.to_s).to_sym); res << e; end
    res
  end

end
