require 'scanner'
require 'tokens'
require 'pp'

# Base-class for all Parsers.
# Defines some common methods for parsing sourcecode.
class ParserBase
  include Tokens

  # The constructor takes a Scanner instance as an argument
  # to read the source code to parse from.
  def initialize(scanner)
    @scanner = scanner
  end

  def zero_or_more(sym)
    res = []
    while e = send(("parse_"+sym.to_s).to_sym); res << e; end
    res
  end

  def expect(*args)
    args.each do |a|
      r = @scanner.expect(a)
      return r if r
    end
    return nil
  end

  def expected(name)
    raise "Error: Expected #{name}"
  end

  def nolfws
    @scanner.nolfws
  end

  def ws
    @scanner.ws
  end


  protected

  # Protected accessor method for the scanner object.
  # For use in subclasses.
  def scanner
    @scanner
  end

end
