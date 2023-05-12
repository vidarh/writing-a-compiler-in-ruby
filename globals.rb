
class Globals
  def initialize
    @global_functions = {}
  end

  def keys
    @global_functions.keys
  end

  # Returns the actual name
  def set(fname, function)
    suffix = ""
    i = 0
    if @global_functions[fname]
      while @global_functions[fname + suffix]
        i += 1
        suffix = "__#{i}"
      end
      fname = fname + suffix
    end

    # add the method to the global list of functions defined so far
    # with its "munged" name.
    @global_functions[fname] = function
    fname
  end

  def [] name
    @global_functions[name]
  end

  # We on purpose provide this instead of "each"
  # as the use-case we need is function/method
  # compilation where additional synthesized methods
  # may get added during compilation.
  def until_empty!(&block)
    while f = @global_functions.shift
      # FIXME: Compiler @bug: This gets turned into calling "comma"
      #yield f[0],f[1]
      block.call(f[0],f[1])
    end
  end
end
