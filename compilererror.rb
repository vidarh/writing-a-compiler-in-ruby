# Custom exception classes for expected compiler errors
# These should be caught at the top level and displayed cleanly to the user
# Other exceptions (RuntimeError, etc.) are internal compiler bugs and should crash with stack trace

class CompilerError < StandardError
  attr_reader :filename, :line, :column, :block_start_line

  # Initialize with either a Position object or individual parameters
  # Usage: CompilerError.new(message, position)
  #    or: CompilerError.new(message, filename, line, column, block_start_line)
  def initialize(message, filename_or_pos = nil, line = nil, column = nil, block_start_line = nil)
    super(message)

    # Check if second parameter is a Position object
    if filename_or_pos.respond_to?(:filename) && filename_or_pos.respond_to?(:lineno)
      pos = filename_or_pos
      @filename = pos.filename
      @line = pos.lineno
      @column = pos.col
      @block_start_line = block_start_line
    else
      @filename = filename_or_pos
      @line = line
      @column = column
      @block_start_line = block_start_line
    end
  end

  # ANSI color codes
  COLOR_RESET = "\e[0m"
  COLOR_CYAN = "\e[36m"
  COLOR_RED = "\e[31m"
  COLOR_BRIGHT_RED = "\e[91m"
  COLOR_BOLD_RED = "\e[1;31m"
  COLOR_DIM = "\e[2m"

  # Format multi-line source context with visual column pointer
  # Shows 3 lines before + error line + 2 lines after
  # If block_start_line is provided and outside context, shows that line too
  # Returns formatted string with line numbers and ^ column pointer (with colors)
  def self.format_source_context(filename, lineno, col, block_start_line = nil)
    return "" if !filename || !File.exist?(filename)

    lines = File.readlines(filename)
    return "" if lines.length == 0

    # Calculate range: [lineno - 3, lineno + 2] (1-indexed)
    start_line = lineno - 3
    start_line = 1 if start_line < 1
    end_line = lineno + 2
    end_line = lines.length if end_line > lines.length

    result = ""

    # If block_start_line is outside the normal context range, show it separately
    if block_start_line && block_start_line < start_line && block_start_line >= 1
      block_line_text = lines[block_start_line - 1]
      # Remove trailing newline if present
      block_line_text.chomp! if block_line_text

      result = result + "#{COLOR_DIM}  #{block_start_line}  #{block_line_text}#{COLOR_RESET}\n"
      result = result + "#{COLOR_DIM}  ...#{COLOR_RESET}\n"
    end

    line_num = start_line
    while line_num <= end_line
      line_idx = line_num - 1  # Convert to 0-indexed
      is_error_line = line_num == lineno
      marker = is_error_line ? ">" : " "
      line_text = lines[line_idx]
      # Remove trailing newline if present (File.readlines includes newlines)
      line_text.chomp! if line_text

      # Format with colors: error line in bold red, normal lines with cyan line numbers
      if is_error_line
        result = result + "#{COLOR_CYAN}  #{line_num}#{COLOR_BOLD_RED}#{marker}#{COLOR_RESET} #{COLOR_RED}#{line_text}#{COLOR_RESET}\n"
      else
        result = result + "#{COLOR_CYAN}  #{line_num}#{marker}#{COLOR_RESET} #{line_text}\n"
      end

      # Add column pointer after error line
      if is_error_line && col
        # Calculate spaces: 2 (indent) + line_num digits + 1 (marker) + 1 (space) + col
        pointer_offset = 2 + line_num.to_s.length + 1 + 1 + col
        spaces = ""
        i = 0
        while i < pointer_offset
          spaces = spaces + " "
          i = i + 1
        end
        result = result + spaces + "#{COLOR_BRIGHT_RED}^#{COLOR_RESET}\n"
      end

      line_num = line_num + 1
    end

    return result
  end

  # Override message to automatically include source context
  def message
    base_message = super
    if @filename && @line
      context = CompilerError.format_source_context(@filename, @line, @column, @block_start_line)
      return base_message + "\n" + context
    end
    return base_message
  end
end

class ParseError < CompilerError
end

class ShuntingYardError < CompilerError
end
