

class Arg
  attr_reader :name,:rest
  def initialize name, *modifiers
    @name = name
    modifiers.each do |m|
      @rest = true if m == :rest
    end
  end

  def rest?; @rest; end  
  def type
    rest? ? :argaddr : :arg
  end
end

class Function
  attr_reader :args,:body
  def initialize args,body
    @body = body
    @rest = false
    @args = args.collect do |a|
      arg = Arg.new(*[a].flatten)
      @rest = true if arg.rest?
      arg
    end
  end

  def rest?; @rest; end
  def get_arg(a)
    if a == :numargs
      # This is a bit of a hack, but it turns :numargs
      # into a constant for any non-variadic function
      return rest? ? [:lvar,-1] : [:int,args.size]
    end

    args.each_with_index do |arg,i|
      return [arg.type,i] if arg.name == a
    end

    return nil
  end
end

