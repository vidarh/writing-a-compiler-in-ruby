
class Globals
  def initialize
    @global_functions = {}
  end

  # Returns the actual name
  def set(fname, function)
    suffix = ""
    i = 0
    while @global_functions[fname + suffix]
      i += 1
      suffix = "__#{i}"
    end
    fname = fname + suffix

    # add the method to the global list of functions defined so far
    # with its "munged" name.
    @global_functions[fname] = function
    fname
  end

  # We on purpose provide this instead of "each"
  # as the use-case we need is function/method
  # compilation where additional synthesized methods
  # may get added during compilation.
  def until_empty!
    while f = @global_functions.shift
      yield f[0],f[1]
    end
  end
end
