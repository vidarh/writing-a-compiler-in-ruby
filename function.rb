# Represents a function argument.
# Can also be a list of arguments if :rest is specified in modifiers
# for variable argument functions.
class Arg
  attr_reader :name, :rest, :default

  # The local variable offset for this argument, if it
  # has a default
  attr_accessor :lvar

  def initialize(name, *modifiers)
    raise "Internal error: Arg.name must be Symbol; '#{name.inspect}'" if !name.is_a?(Symbol)

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
  attr_reader :args, :body, :scope, :name, :break_label, :arity_check

  # True for a method defined inside a block (`Class.new(Base) do def m; ...; end end`). Such a method is
  # installed on a class only known at runtime, so its lexical class_scope (the enclosing Object) is NOT
  # the class it ends up on -- `super` must therefore resolve via self.class.superclass at runtime rather
  # than by the (wrong) lexical class name. Set by compile_defm.
  attr_accessor :block_def

  # Number of variables with defaults that we need to
  # allocate local stack space for.
  attr_reader :defaultvars

  # Constructor for functions.
  # Takes an argument list, a body of expressions as well as
  # the scope the function was defined in. For methods this is a
  # class scope.
  def initialize(name, args, body, scope, break_label, arity_check = true)
    @name = name
    @body = body || []
    @rest = false
    @arity_check = arity_check
    args ||= []

    @defaultvars = 0

    # If break should go to an outer function,
    # break_label is not nil
    @break_label = break_label 

    if args.last.kind_of?(Array)
      @blockarg = args.pop[0] if  args.last[1] == :block
    end

    @args = args.collect do |a|
      # a is either a bare param (Symbol) or a structured one (Array). [a].flatten(1) built one/two
      # throwaway Arrays per arg to normalise; splat the Array directly (or wrap a scalar) instead.
      arg = Arg.new(*(a.is_a?(Array) ? a : [a]))
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
    i = 0
    len = args.length
    while i < len
      arg = args[i]
      if arg.default && (arg.name == a)
        raise "Expected to have a lvar assigned for #{arg.name}" if !arg.lvar
        return [:lvar, arg.lvar]
      end
      i += 1
    end
    nil
  end

  def get_arg(a)
    # Previously, we made this a constant for non-variadic
    # functions. The problem is that we need to be able
    # to trigger exceptions for calls with the wrong number
    # of arguments, so we need this always.
    return [:lvar, -1] if a == :numargs

    # FIXME
    # @bug: r does not get set to nil if this line is not here.
    r = nil
    r = get_lvar_arg(a) if @defaults_assigned || a[0] == ?#
    return r if r
    raise "Expected lvar - #{a} / #{args.inspect}" if a[0] == ?#

    a = :__closure__ if a == @blockarg
    i = 0
    len = args.length
    while i < len
      arg = args[i]
      return [arg.type, i] if arg.name == a
      i += 1
    end

    return @scope.get_arg(a)
  end
end
