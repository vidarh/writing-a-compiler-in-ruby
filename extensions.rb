# some useful extension methods to existing classes

module Enumerable
  # returns all but the first elements
  def rest
    self[1..-1]
  end
end

if RUBY_VERSION < "1.9"
  class String
    def ord
      self[0].to_i
    end
  end
end

class Array
  # Visit each node depth first
  # If the given block return :skip,
  # no children of this node gets visited
  # If the given block returns :stop,
  # no further visitation is done.
  #
  # Only Array / Expr nodes get visited.
  #
  # You can pass symbols that will be checked
  # against self[0] to determine whether or
  # not to yield
  #
  # FIXME: This should be moved to AST::Expr
  # when the parser is cleaned up to never
  # create "raw" arrays
  def depth_first(*arg, &block)
    ret = yield(self) if arg.size == 0 || arg.member?(self[0])
    return :stop if ret == :stop
    return true if ret == :skip

    self.each do |n|
      ret = n.depth_first(*arg, &block) if n.is_a?(Array)
      return :stop if ret == :stop
    end
    return true
  end
end
