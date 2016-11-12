# some useful extension methods to existing classes

module Enumerable
  # returns all but the first elements
  def rest
    self[1..-1]
  end
end

class Array

  # FIXME: Because of lack of "include" support
  def rest
    self[1..-1]
  end

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
    # FIXME: Temporary workaround: If
    # "ret" is used in the if statements
    # further down, but only initialized
    # in the if-block, it will be used
    # without first being initialized.
    # Need to ensure that all variables
    # gets initialized before use.
    ret = nil
    if arg.size == 0 || arg.member?(self[0])
      ret = yield(self) 
    end
    return :stop if ret == :stop
    return true if ret == :skip

    # FIXME: Temporary workaround; if
    # "arg" is used directly within
    # the block below then one of the
    # rewrites fail and causes it to
    # be incorrectly initialized
    a = arg
    self.each do |n|
      ret = n.depth_first(*a, &block) if n.is_a?(Array)
      return :stop if ret == :stop
    end
    return true
  end
end
