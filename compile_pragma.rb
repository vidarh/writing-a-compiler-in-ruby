
# Compile directives intended at the compiler.
# Currently only %s(__compiler_internal ...) used to designate locations to
# inject various lists.
#

class Compiler

  def output_symbol_list(scope)
    @symbols.each do |s|
      compile_assign(scope, symbol_name(s), [:call, :__get_symbol, s])
    end
    Value.new([:global, :nil])
  end

  def compile___compiler_internal scope, type, *args
    case type
    when :symbol_list
      return output_symbol_list(scope)
    end

    error("Unknown pragma: #{type}")
  end
end
