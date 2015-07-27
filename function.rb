# Represents a function argument.
# Can also be a list of arguments if :rest is specified in modifiers
# for variable argument functions.
class Arg
  attr_reader :name, :rest, :default

  # The local variable offset for this argument, if it
  # has a default
  attr_accessor :lvar

  def initialize(name, *modifiers)
    @name = name
    # @rest indicates if we have
    # a variable amount of parameters
    @rest = modifiers.include?(:rest)
    @default = modifiers[0] == :default ? modifiers[1] : nil
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
  attr_reader :args, :body, :scope, :name

  # Number of variables with defaults that we need to
  # allocate local stack space for.
  attr_reader :defaultvars

  # Constructor for functions.
  # Takes an argument list, a body of expressions as well as
  # the scope the function was defined in. For methods this is a
  # class scope.
  def initialize(name, args, body, scope)
    @name = name
    @body = body || []
    @rest = false
    args ||= []

    @defaultvars = 0

    @blockarg = args.pop if args[-1].kind_of?(Array) && args[-1][0] == :block

    @args = args.collect do |a|
      arg = Arg.new(*[a].flatten(1))
      if arg.default
        arg.lvar = @defaultvars
        @defaultvars += 1
      end

      @rest = true if arg.rest?
      arg
    end

    # Default values have not yet been assigned for this.
    @defaults_assigned = false

    @scope = scope
  end

  def rest?
    @rest
  end

  def minargs
    @args.length - (rest? ? 1 : 0) - @defaultvars
  end

  def maxargs
    rest? ? 99999 : @args.length
  end

  def process_defaults
    self.args.each_with_index do |arg,index|
      # FIXME: Should check that there are no "gaps" without defaults?
      if (arg.default)
        yield(arg,index)
      end
    end
    @defaults_assigned = true
  end

  def lvaroffset
    @defaultvars
  end

  # For arguments with defaults only, return the [:lvar, arg.lvar] value
  def get_lvar_arg(a)
    a = a.to_s[1..-1].to_sym if a[0] == ?#
    args.each_with_index do |arg,i|
      if arg.default && (arg.name == a)
        raise "Expected to have a lvar assigned for #{arg.name}" if !arg.lvar
        return [:lvar, arg.lvar]
      end
    end
    nil
  end

  def get_arg(a)
    # Previously, we made this a constant for non-variadic
    # functions. The problem is that we need to be able
    # to trigger exceptions for calls with the wrong number
    # of arguments, so we need this always.
    return [:lvar, -1] if a == :numargs

    r = get_lvar_arg(a) if @defaults_assigned || a[0] == ?#
    return r if r
    raise "Expected lvar - #{a} / #{args.inspect}" if a[0] == ?#

    args.each_with_index do |arg,i|
      return [arg.type, i] if arg.name == a
    end

    return @scope.get_arg(a)
  end
end
