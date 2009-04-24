# Represents a function argument.
# Can also be a list of arguments if :rest is specified in modifiers
# for variable argument functions.
class Arg
  attr_reader :name, :rest

  def initialize(name, *modifiers)
    @name = name
    # @rest indicates if we have
    # a variable amount of parameters
    @rest = modifiers.include?(:rest)
  end

  def rest?
    @rest
  end

  def type
    rest? ? :argaddr : :arg
  end
end

# Represents a function.
# Takes arguments and a body of code.
class Function
  attr_reader :args, :body, :cscope

  # Constructor for functions.
  # Takes an argument list, a body of expressions as well as an
  # optional class scope, if the function is defined within a class.
  # The class scope is needed to refer to instance & class variables
  # inside the method.
  def initialize(args, body, class_scope = nil)
    @body = body
    @rest = false
    @args = args.collect do |a|
      arg = Arg.new(*[a].flatten)
      @rest = true if arg.rest?
      arg
    end

    @cscope = class_scope
  end

  def rest?
    @rest
  end

  # A function is a method, if its class scope isn't nil.
  def is_method?
    @cscope != nil
  end

  def get_arg(a)
    # if we have a method, let's check first,
    # if the class scope has the argument defined.
    if is_method?
      return @cscope.get_arg(a)
    end

    if a == :numargs
      # This is a bit of a hack, but it turns :numargs
      # into a constant for any non-variadic function
      return rest? ? [:lvar, -1] : [:int, args.size]
    end

    args.each_with_index do |arg,i|
      return [arg.type, i] if arg.name == a
    end

    return nil
  end
end
