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

  def expect(*args)
    args.each do |a|
      r = @s.expect(a)
      return r if r
    end
    return nil
  end

  def expected(name)
    raise "Error: Expected #{name}"
  end

  def ws
    @s.ws
  end

end
