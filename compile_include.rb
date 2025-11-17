
#
# "include" in Ruby is fairly complex:
#
#  * For each named object (constants, methods) in the module,
#    if the object has not been defined *in the class*, it will
#    be overridden.
#
#  * If a method of the same name exists in the supercass, it
#    will be aliased
#
#  * If a method is *subsequently* defined in the module, it will
#    be added to the casses that include it.
#
# Basically this is as if you inject an extra super-class between
# the class and its real super-class, similar to eigen-classes.
#
# FIXME: Verify reality priority of superclass vs. eigenclass.
#
# Biggest problem is instance variables: Instance variabes in
# a module must use access methods in the client classes.
#
# Either hash lookup, or we may consider synthesizing accessors
# and auto-add them to classes that include it. Issue is
#
# FIXME: Verify logic with multiple includes.
#
#

class Compiler
  def compile_include(scope, incl, pos = nil)

    # At this point we want to:
    #
    # 1. Attach scope of included module, so static constant lookups
    #    works (are re-directed to original class.

    # Handle nested module syntax: include Foo::Bar
    # Parser creates [:deref, :Foo, :Bar] for this
    if incl.is_a?(Array) && incl[0] == :deref && incl.length == 3
      # Resolve Foo::Bar to get the module scope
      parent_scope_name = incl[1]
      child_constant_name = incl[2]
      parent_scope = scope.find_constant(parent_scope_name)
      if parent_scope && parent_scope.is_a?(ModuleScope)
        mscope = parent_scope.find_constant(child_constant_name)
      else
        mscope = nil
      end
    else
      mscope = scope.find_constant(incl)
    end

    if !mscope
      # Use position info from wrapping expression
      if pos
        raise CompilerError.new("Module not found: #{incl}", pos)
      else
        raise CompilerError.new("Module not found: #{incl}")
      end
    end
    scope.include_module(mscope)

    # 2. Call __include_module at runtime to copy vtable entries
    #    This runtime function loops through all vtable slots and copies
    #    from the module to the class if the class slot is uninitialized.
    #    (Note: __include_module has built-in null check, so safe to call even if module not yet initialized)

    # Generate runtime call: __include_module(target, ModuleName)
    # In class/module scope: target is self (the class being defined)
    # In global scope: target is Object (top-level include adds to Object)
    # Use the module scope name (which is flattened for nested modules)
    module_name = mscope.name.to_sym
    if scope.is_a?(GlobalScope)
      compile_eval_arg(scope, [:sexp, [:call, :__include_module, [:Object, module_name]]])
    else
      compile_eval_arg(scope, [:sexp, [:call, :__include_module, [:self, module_name]]])
    end

    # FIXME:
    # - Ensure we handle eigenclasses properly.
    # - Ensure *subsequent* changes are updated correctly (if module methods change after include).
    # - Dynamic constant lookups.

    Value.new([:subexpr])
  end
end
