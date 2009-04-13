# some useful extension methods to existing classes

module Enumerable
  # returns all but the first elements
  def rest
    self[1..-1]
  end
end
