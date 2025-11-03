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
end

class ParseError < CompilerError
end

class ShuntingYardError < CompilerError
end
