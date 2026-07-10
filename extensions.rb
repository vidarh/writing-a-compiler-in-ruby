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
  # Public entry: normalise the filter symbols to a single Array ONCE, then recurse without re-splatting.
  # The old code did `*arg` on entry AND `*a` on every recursive call, so each AST node allocated one (in
  # fact two) throwaway Arrays just to pass `arg` down -- one of the largest compile allocators/CPU costs
  # (Array#depth_first ~9% CPU). Threading the array directly does it once for the whole traversal.
  def depth_first(*arg, &block)
    # Materialise the block into a Proc ONCE here and thread it as a REGULAR argument through the
    # recursion, rather than re-passing `&block` (and calling `yield`) at every node. The self-hosted
    # compiler boxes a `&block` method parameter into a closure on EVERY call, so with N AST nodes the old
    # form allocated ~N closures per pass (x ~50 passes) -- a large self-hosted GC cost that MRI avoids via
    # lazy block passing. Passing the Proc as a value allocates it once and reuses it.
    __depth_first(arg, block)
  end

  def __depth_first(arg, block)
    # FIXME: Temporary workaround: If
    # "ret" is used in the if statements
    # further down, but only initialized
    # in the if-block, it will be used
    # without first being initialized.
    # Need to ensure that all variables
    # gets initialized before use.
    ret = nil
    # filter is almost always 0 or 1 symbols; avoid Enumerable#member?'s iteration in those cases
    al = arg.length
    if al == 0 || (al == 1 ? arg[0] == self[0] : arg.member?(self[0]))
      ret = block.call(self)
    end
    return :stop if ret == :stop
    return true if ret == :skip

    # FIXME: Temporary workaround; if
    # "arg" is used directly within
    # the block below then one of the
    # rewrites fail and causes it to
    # be incorrectly initialized
    a = arg
    # Index while-loop instead of `self.each do |n|`: depth_first runs over the whole AST ~50 times per
    # compile, so the per-node block dispatch adds up. (Also the codebase prefers `while` over `each` in
    # hot self-hosted paths -- see ast_marshal.)
    i = 0
    len = self.length
    while i < len
      n = self[i]
      if n.is_a?(Array)
        ret = n.__depth_first(a, block)
        return :stop if ret == :stop
      end
      i += 1
    end
    return true
  end
end
