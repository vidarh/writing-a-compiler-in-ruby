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


  # Format multi-line source context with visual column pointer
  # Shows 3 lines before + error line + 2 lines after
  # Returns formatted string with line numbers and ^ column pointer
  def format_source_context(filename, lineno, col)
    return "" if !filename || !File.exist?(filename)

    lines = File.readlines(filename)
    return "" if lines.length == 0

    # Calculate range: [lineno - 3, lineno + 2] (1-indexed)
    start_line = lineno - 3
    start_line = 1 if start_line < 1
    end_line = lineno + 2
    end_line = lines.length if end_line > lines.length

    result = "\n"
    line_num = start_line
    while line_num <= end_line
      line_idx = line_num - 1  # Convert to 0-indexed
      marker = line_num == lineno ? ">" : " "
      line_text = lines[line_idx]
      # Remove trailing newline for display
      line_text = line_text[0..-2] if line_text && line_text[-1] == 10

      # Format: "  123> line content" or "  123  line content"
      result = result + "  #{line_num}#{marker} #{line_text}\n"

      # Add column pointer after error line
      if line_num == lineno && col
        # Calculate spaces: 2 (indent) + line_num digits + 1 (marker) + 1 (space) + col
        pointer_offset = 2 + line_num.to_s.length + 1 + 1 + col
        spaces = ""
        i = 0
        while i < pointer_offset
          spaces = spaces + " "
          i = i + 1
        end
        result = result + spaces + "^\n"
      end

      line_num = line_num + 1
    end

    return result
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
      error_location = "#{filename}(#{@scanner.lineno}:#{@scanner.col})"
      context = format_source_context(filename, @scanner.lineno, @scanner.col)
      full_message = "Parse error: #{error_location}: #{message}#{context}\nAfter: '#{str}'"

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
