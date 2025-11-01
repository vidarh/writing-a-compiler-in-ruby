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
  # Error message contains filename, line number, column number, and context.
  # Shows context BEFORE the error position (more useful than after).
  # Set COMPILER_DEBUG=1 for additional technical details.
  def error(message)
    lineno = @scanner.lineno
    col = @scanner.col

    # Build the error message
    if from_file?
      error_msg = "Parse error: #{filename}:#{lineno}:#{col}: #{message}"
    else
      error_msg = "Parse error: line #{lineno}, column #{col}: #{message}"
    end

    # Add context snippet if available
    # (Context will be improved in future to show actual source line)
    if ENV['COMPILER_DEBUG']
      # Show what comes next (for debugging)
      i = 0
      next_chars = ""
      while (i < 30) && (c = @scanner.get)
        next_chars << c
        i += 1
      end
      error_msg << "\n\n[DEBUG] Next characters: '#{next_chars}'"
    end

    raise error_msg
  end

  protected

  # Protected accessor method for the scanner object.
  # For use in subclasses.
  def scanner
    @scanner
  end

end
