
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

  # Build each interned frozen string literal once at startup: __FSL_n = __get_frozen_string(<content>).
  # `content` is the plain literal text; compile_eval_arg lowers it to the shared rodata buffer address, so
  # __get_frozen_string allocates + freezes one String per unique content. Loads of __FSL_n (emitted by
  # rewrite_strconst) then reuse it. Runs at the `frozen_string_list` pragma, alongside symbol interning.
  def output_frozen_string_list(scope)
    @frozen_string_constants.each do |content, slot|
      compile_assign(scope, slot, [:call, :__get_frozen_string, content])
    end
    Value.new([:global, :nil])
  end

  def compile___compiler_internal scope, type, *args
    case type
    when :symbol_list
      return output_symbol_list(scope)
    when :frozen_string_list
      return output_frozen_string_list(scope)
    when :type_effect
      # A declaration consumed by the type inferencer (type_inference.rb compute_effects) to describe a
      # reflective helper's net vtable effect. Pure annotation -- emit NO code.
      return Value.new([:global, :nil])
    end

    error("Unknown pragma: #{type}")
  end
end
