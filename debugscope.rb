
class Scope
  def dump(indent = 0,data = {})
    data.sort.each do |k,v|
      if v.kind_of?(Scope)
        STDERR.puts "#{" "*indent*2}#{k}:"
        v.dump(indent + 1)
      else
        STDERR.puts "#{" "*indent*2}#{k}: #{v.inspect}"
      end
    end
  end
end

class GlobalScope < Scope
  def dump(indent = 0,data = {})
    super(indent, @globals)
  end
end

class ClassScope < Scope
  def dump(indent = 0,data = {})
    # FIXME: Don't add e.g. Token__Atom, and fix lookup so it's irrelevant
    if !@constants.empty?
      STDERR.puts "#{" "*indent*2}CONSTANTS:"
      super(indent + 1, @constants)
    end
    if !@instance_vars.empty?
      STDERR.puts "#{" "*indent*2}IVARS:"
      @instance_vars.sort.each do |ivar|
        STDERR.puts "#{" "*(indent + 1)*2}#{ivar}"
      end
    end
  end
end
