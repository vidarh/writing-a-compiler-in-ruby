require 'scanner'
require 'tokens'
require 'pp'
require 'ast'

# Base-class for all Parsers.
# Defines some common methods for parsing sourcecode.
class ParserBase
  include Tokens
  include AST

  # The constructor takes a Scanner instance as an argument
  # to read the source code to parse from.
  def initialize(scanner)
    @scanner = scanner
  end

  def zero_or_more(sym)
    res = []
    s = "parse_#{sym.to_s}".to_sym
    while e = send(s)
        res << e;
    end
    res
  end

  def position
    @scanner.position
  end

  def expect(*args)
    args.each do |a|
      r = @scanner.expect(a)
      return r if r
    end
    return nil
  end

  def keyword(arg)
    Tokens::Keyword.expect(@scanner,arg)
  end

  def expected(name)
    error("Expected: #{name}")
  end

  def nolfws
    @scanner.nolfws
  end

  def ws
    @scanner.ws
  end

  # Returns filename from which parser reads code.
  def filename
    @scanner.filename
  end

  # Returns true, if the parser gets code from a file.
  def from_file?
    !@scanner.filename.nil?
  end


  # Output error message by raising an exception.
  # Error message contains filename and linenumber, if reading from a file.
  # Otherwise, the message only contains the current linenumber and the error message.
  def error(message)
    if from_file?
      raise "Parse error: #{filename}(#{@scanner.lineno}):  #{message}"
    else
      raise "Parse error: #{@scanner.lineno}: #{message}"
    end
  end

  protected

  # Protected accessor method for the scanner object.
  # For use in subclasses.
  def scanner
    @scanner
  end

end
