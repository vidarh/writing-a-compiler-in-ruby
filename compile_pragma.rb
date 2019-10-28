
# Compile directives intended at the compiler.
# Currently only %s(__compiler_internal ...) used to designate locations to
# inject various lists.
#

class Compiler
  #
  # FIXME: We could go one better with this, and generate the
  # objects "raw". Will revisit that once I see if it is worth it.
  #
  def output_integer_list(scope)
    @integers.each do |i|
      compile_assign(scope, int_name(i), [:call, :__int, i])
    end
    Value.new([:global, :nil])
  end

  def compile___compiler_internal scope, type, *args
    case type
    when :integer_list
      return output_integer_list(scope)
    end

    error("Unknown pragma: #{type}")
  end
end
