
class Compiler

  # Compiles a method definition and updates the
  # class vtable.
  def compile_defm(scope, name, args, body)
    orig_scope = scope
    scope = scope.class_scope

    if name.is_a?(Array)
      compile_eigenclass(scope, name[0], [[:defm, name[1], args, body]])
      return Value.new([:subexpr])
    end

    # FIXME: Replace "__closure__" with the block argument name if one is present
    f = Function.new(name,[:self,:__closure__]+args, body, scope, @e.get_local) # "self" is "faked" as an argument to class methods

    #@e.comment("method #{name}")

    cleaned = clean_method_name(name)
    fname = "__method_#{scope.name}_#{cleaned}"
    fname = @global_functions.set(fname, f)

    # Register method in vtable (offsets are global, same for all classes)
    scope.set_vtable_entry(name, fname, f)
    v = scope.vtable[name]

    # Call __set_vtable with :self (resolved through scope chain)
    # For EigenclassScope, :self resolves to the eigenclass object from LocalVarScope
    # For regular ClassScope, :self resolves to the class object
    compile_eval_arg(scope,[:sexp, [:call, :__set_vtable, [:self, v.offset, fname.to_sym]]])


    # This is taken from compile_defun - it does not necessarily make sense for defm
    return Value.new([:subexpr]) #addr, clean_method_name(fname)])
  end


  def compile_module(scope,name, *exps)
    # FIXME: This is a cop-out that will cause horrible
    # crashes - they are not the same (though nearly)
    compile_class(scope,name, *exps)
  end

  # Helper method to search for a method in the class vtable chain (including superclasses)
  def find_method_in_vtable_chain(class_scope, method_name)
    current = class_scope
    while current
      entry = current.vtable[method_name]
      return entry if entry
      # Walk up the superclass chain
      current = current.superclass
    end
    nil
  end

  # Compiles method aliasing: alias new_name old_name
  # Creates a new vtable entry that points to the same implementation as the old method
  # Also handles global variable aliasing: alias $new $old
  def compile_alias(scope, new_name, old_name)
    # Check if this is a global variable alias (both names start with $)
    if old_name.to_s[0] == ?$ && new_name.to_s[0] == ?$
      # Global variable aliasing - just make them refer to the same storage
      # Get the aliased name for the old global
      old_arg = scope.get_arg(old_name)
      if old_arg[0] != :global
        error("Cannot alias undefined global variable '#{old_name}'")
      end

      # Find the GlobalScope - walk up the scope chain
      global_scope = scope
      while global_scope && !global_scope.is_a?(GlobalScope)
        # Try to find parent scope via various methods
        if global_scope.respond_to?(:class_scope) && global_scope.class_scope.is_a?(GlobalScope)
          global_scope = global_scope.class_scope
        elsif global_scope.next
          global_scope = global_scope.next
        else
          global_scope = nil
        end
      end

      if global_scope && global_scope.respond_to?(:add_global_alias)
        global_scope.add_global_alias(new_name, old_name)
      end

      # No runtime code needed - aliasing is compile-time only for globals
      return Value.new([:subexpr])
    end

    class_scope = scope.class_scope

    # Ensure both old and new method names have vtable entries
    # add_vtable_entry allocates an offset if one doesn't exist
    old_entry = class_scope.add_vtable_entry(old_name)
    new_entry = class_scope.add_vtable_entry(new_name)

    # Generate runtime code to copy the function pointer from old to new offset
    # This uses __alias_method_runtime which just does: vtable[new_off] = vtable[old_off]
    compile_eval_arg(scope, [:sexp, [:call, :__alias_method_runtime, [:self, new_entry.offset, old_entry.offset]]])

    return Value.new([:subexpr])
  end

  def mk_new_class_object(*args)
    [:sexp, [:call, :__new_class_object, args]]
  end

  def mk_class(ob)
    [:index,ob,0]
  end

  # FIXME: compiler @bug workaround. See #compile_eigenclass
  def compile_ary_do(lscope, exps)
    exps.each do |e|
      compile_do(lscope, e)
    end
  end

  # Find the nearest ClassScope by traversing the scope chain
  # Returns Object's ClassScope if no ClassScope found in chain
  def find_class_scope(scope)
    current = scope
    while current
      return current if current.is_a?(ClassScope)
      current = current.next
    end
    # No ClassScope found - return Object's ClassScope
    @global_scope.class_scope
  end

  def compile_eigenclass(scope, expr, exps)
    @e.comment("=== Eigenclass start (using nested let)")

    # Find the enclosing ClassScope for method registration
    class_scope = find_class_scope(scope)

    # Eigenclasses are Class objects, so they use Class's klass_size
    # Get Class's ClassScope to determine the correct klass_size
    eksize = @classes[:Class].klass_size

    # Using nested let()'s for clean scope management
    # Outer let: evaluate expr and save to __eigenclass_obj
    unique_id = @e.get_local[2..-1]
    @e.comment("Eigenclass #{unique_id}")
    let(scope, :__eigenclass_obj) do |outer_scope|

      compile_eval_arg(outer_scope, [:assign, :__eigenclass_obj, expr])

      let(outer_scope, :self) do |lscope|

        compile_eval_arg(lscope, [:assign, :self,
          mk_new_class_object(
            eksize,                                # size = Class's klass_size
            [:index, :__eigenclass_obj, 0],        # superclass = obj.class
            eksize,                                # ssize = Class's klass_size
            0                                      # classob = 0 (defaults to Class)
          )
        ])

        compile_eval_arg(lscope, [:assign, [:index, :__eigenclass_obj, 0], :self])

        # Set eigenclass name
        compile_eval_arg(lscope, [:assign, [:index, :self, 2], "Eigenclass_#{unique_id}"])

        escope = EigenclassScope.new(lscope, "Eigenclass_#{unique_id}", @vtableoffsets, class_scope)

        # Compile eigenclass body with LocalVarScope
        # When compile_defm is called, it will find escope via lscope.class_scope
        # Methods will register in escope's vtable, :self resolves from lscope
        compile_ary_do(escope, exps)

        # Return the eigenclass
        compile_eval_arg(lscope, :self)
      end
    end

    @e.comment("=== Eigenclass end")
    return Value.new([:subexpr], :object)
  end


  # Compiles a class definition.
  # Takes the current scope, the name of the class as well as a list of expressions
  # that belong to the class.
  def compile_class(scope, name,superclass, *exps)
    superc = name == :Class ? nil : @classes[superclass]

    # Check if this is an eigenclass definition: class << obj
    if name.is_a?(Array) && name[0] == :eigen
      return compile_eigenclass(scope, name[1], *exps)
    end

    # Check if this is a global namespace definition: class ::A
    # Parser creates [:global, :A] for this
    force_global = false
    if name.is_a?(Array) && name[0] == :global
      force_global = true
      name = name[1]
    end

    # Handle nested class syntax: class Foo::Bar
    # Parser creates [:deref, :Foo, :Bar] for this
    nested_parent = nil
    nested_child = nil
    explicit_namespace = false  # True when using Foo::Bar syntax (name contains full path)
    if name.is_a?(Array) && name[0] == :deref
      # Handle nested class/module names like Foo::Bar or Foo::Bar::Baz
      # Flatten the nested deref structure to a single name like Foo__Bar__Baz
      parts = []
      n = name
      while n.is_a?(Array) && n[0] == :deref && n.length == 3
        if n[2].is_a?(Symbol)
          parts.unshift(n[2])
          n = n[1]
        else
          # Non-symbol child (runtime expression) - not supported
          error("Complex nested class/module syntax not supported: #{name.inspect}", scope)
        end
      end
      if n.is_a?(Symbol)
        parts.unshift(n)
        # Flatten to Foo__Bar__Baz for the class name
        name = parts.join("__").to_sym
        # For tracking parent scope, use first part as nested_parent, rest as nested_child
        # This is simplified - we're effectively creating a flat namespace
        nested_parent = parts[0..-2].join("__").to_sym if parts.length > 1
        nested_child = parts.last if parts.length > 1
        # Mark that we used explicit namespace syntax - don't add parent prefix
        explicit_namespace = true
      else
        # Parent is not a symbol (runtime expression) - not supported
        error("Complex nested class/module syntax not supported: #{name.inspect}", scope)
      end
    end

    # Determine the parent scope for this class definition
    # If force_global (class ::A), always use global scope
    # Otherwise walk scope chain to find ModuleScope/ClassScope, but if we hit GlobalScope first, use it
    if force_global
      parent_scope = @global_scope
    else
      parent_scope = scope
      while parent_scope && !parent_scope.is_a?(ModuleScope) && parent_scope != @global_scope
        parent_scope = parent_scope.next
      end
      parent_scope ||= @global_scope
    end

    # Calculate the fully qualified name for this class
    # If explicit_namespace (class Foo::Bar syntax), use the flattened name directly
    # If parent is a ModuleScope/ClassScope, prefix with parent name (e.g., "Foo__Bar")
    # If parent is GlobalScope, use just the name (e.g., "Bar")
    if explicit_namespace
      # Name already contains full path (e.g., ClassSpecs__L), don't add prefix
      fully_qualified_name = name.to_sym
    elsif parent_scope.is_a?(ModuleScope)
      fully_qualified_name = "#{parent_scope.name}__#{name}".to_sym
    else
      fully_qualified_name = name.to_sym
    end

    # Check if this fully qualified class already exists
    # This ensures nested classes don't collide with global classes of the same name
    cscope = @classes[fully_qualified_name]

    # If not found with fully qualified name, try the simple name
    # This handles the case where a module/class was defined at global scope
    # and is being reopened from inside a method (where parent_scope is Object)
    # Only do this for symbol names (not runtime-computed names like [:index, :__env__, 4])
    if !cscope && parent_scope.is_a?(ModuleScope) && parent_scope.name == "Object" && name.is_a?(Symbol)
      cscope = @classes[name]
      # If found, use the existing scope's name for consistency
      fully_qualified_name = name if cscope
    end

    # If cscope is nil, the class hasn't been defined yet - create it
    if !cscope
      # Pass scope as local_scope for accessing enclosing local variables
      local_scope = (scope != parent_scope) ? scope : nil
      cscope = ClassScope.new(parent_scope, name, @vtableoffsets, superc, local_scope)
      @classes[fully_qualified_name] = cscope
      @global_scope.add_constant(fully_qualified_name, cscope)
      # Also register in parent scope so lookups work
      if parent_scope.respond_to?(:add_constant) && parent_scope != @global_scope
        # name should be a symbol at this point, but check just in case
        register_name = name.is_a?(Symbol) ? name : fully_qualified_name
        parent_scope.add_constant(register_name, cscope)
      end
    else
      # Class is being reopened - update local_scope for this invocation
      # This allows accessing local variables from the enclosing scope
      local_scope = (scope != parent_scope) ? scope : nil
      cscope.local_scope = local_scope if local_scope
    end

    # For nested class/module Foo::Bar, register Bar in Foo's namespace
    # This must happen outside the !cscope check because modules are created by transform phase
    if nested_parent && nested_child
      parent_module = @global_scope.find_constant(nested_parent)
      if parent_module && parent_module.respond_to?(:add_constant)
        parent_module.add_constant(nested_child, cscope)
      end
    end

    @e.comment("=== class #{cscope.name} ===")


    @e.evict_regs_for(:self)


    name = cscope.name.to_sym
    # The check for :Class and :Kernel is an "evil" temporary hack to work around the bootstrapping
    # issue of creating these class objects before Object is initialized. A better solution (to avoid
    # demanding an explicit order would be to clear the Object constant and make sure __new_class_object
    #does not try to deref a null pointer
    #
    sscope = (name == superclass or name == :Class or name == :Kernel) ? nil : @classes[superclass]

    ssize = sscope ? sscope.klass_size : nil
    ssize = 0 if ssize.nil?

    classob = :Class
    if superc && superc.name != "Object"
      classob = [:index, superc.name.to_sym , 0]
    end
    compile_eval_arg(scope, [:if,
                             [:sexp,[:eq, name, 0]],
                             # then
                             [:assign, name.to_sym,
                              mk_new_class_object(cscope.klass_size, superclass, ssize, classob)
                             ]])

    @global_constants << name

    # In the context of "cscope", "self" refers to the Class object of the newly instantiated class.
    # Previously we used "@instance_size" directly instead of [:index, :self, 1], but when fixing instance
    # variable handling and adding offsets to avoid overwriting instance variables in the superclass,
    # this broke, as obviously we should not be able to directly mess with the superclass's instance
    # variables, so we're intentionally violating encapsulation here.

    compile_exp(cscope, [:assign, [:index, :self, 1], cscope.instance_size])

    # We need to store the "raw" name here, rather than a String object,
    # as String may not have been initialized yet
    compile_exp(cscope, [:assign, [:index, :self, 2], name.to_s])

    exps.each do |e|
      addr = compile_do(cscope, *e)
    end

    @e.comment("=== end class #{name} ===")
    return Value.new([:global, name], :object)
  end

end
