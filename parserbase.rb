require 'compilererror'
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

  def kleene
    res = E[position]
    while e = yield
      res << e
    end
    res
  end

  def position
    @scanner.position
  end

  def literal(str)
    @scanner.expect_str(str)
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
    i = 0
    str = ""
    while (i < 30) && (c = @scanner.get)
      str << c
      i += 1
    end

    if from_file?
      # Format: filename(line:col): message
      # Source context will be added automatically by CompilerError#message
      error_location = "#{filename}(#{@scanner.lineno}:#{@scanner.col})"
      full_message = "Parse error: #{error_location}: #{message}\nAfter: '#{str}'"

      raise ParseError.new(full_message,
                           filename,
                           @scanner.lineno,
                           @scanner.col)
    else
      raise ParseError.new("Parse error: #{@scanner.lineno}: #{message}",
                           nil,
                           @scanner.lineno)
    end
  end

  protected

  # Protected accessor method for the scanner object.
  # For use in subclasses.
  def scanner
    @scanner
  end

end
