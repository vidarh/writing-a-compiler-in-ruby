# Math module - stub implementation

module Math
  # DomainError is raised when a mathematical operation is not defined
  # for the given input (e.g., sqrt of negative number)
  class DomainError < StandardError
  end
end
