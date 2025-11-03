# Custom exception classes for expected compiler errors
# These should be caught at the top level and displayed cleanly to the user
# Other exceptions (RuntimeError, etc.) are internal compiler bugs and should crash with stack trace

class CompilerError < StandardError
  attr_reader :filename, :line, :column

  def initialize(message, filename = nil, line = nil, column = nil)
    super(message)
    @filename = filename
    @line = line
    @column = column
  end

  # Format multi-line source context with visual column pointer
  # Shows 3 lines before + error line + 2 lines after
  # Returns formatted string with line numbers and ^ column pointer
  def self.format_source_context(filename, lineno, col)
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

  # Override message to automatically include source context
  def message
    base_message = super
    if @filename && @line
      context = CompilerError.format_source_context(@filename, @line, @column)
      return base_message + context
    end
    return base_message
  end
end

class ParseError < CompilerError
end

class ShuntingYardError < CompilerError
end
