
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

    # Check if we're in an eigenclass (LocalVarScope marked with eigenclass_scope flag)
    in_eigenclass = orig_scope.is_a?(LocalVarScope) && orig_scope.eigenclass_scope

    # FIXME: Replace "__closure__" with the block argument name if one is present
    f = Function.new(name,[:self,:__closure__]+args, body, scope, @e.get_local) # "self" is "faked" as an argument to class methods

#    @e.comment("method #{name}")

    cleaned = clean_method_name(name)
    if in_eigenclass
      # For eigenclass methods, use a unique identifier to avoid clashes
      # Use the label counter to ensure uniqueness
      unique_id = @e.get_local[2..-1]
      fname = "__method_Eigenclass_#{unique_id}_#{cleaned}"
    else
      fname = "__method_#{scope.name}_#{cleaned}"
    end
    fname = @global_functions.set(fname, f)

    # Register method in vtable (offsets are global, same for all classes)
    scope.set_vtable_entry(name, fname, f)
    v = scope.vtable[name]

    # For eigenclass methods, use the eigenclass object (:self from LocalVarScope)
    # For regular methods, use the class object (:self from ClassScope)
    # FIXME: Compiler bug - ternary operator returns false instead of else branch
    # vtable_scope = in_eigenclass ? orig_scope : scope
    if in_eigenclass
      vtable_scope = orig_scope
    else
      vtable_scope = scope
    end
    compile_eval_arg(vtable_scope,[:sexp, [:call, :__set_vtable, [:self, v.offset, fname.to_sym]]])


    # This is taken from compile_defun - it does not necessarily make sense for defm
    return Value.new([:subexpr]) #addr, clean_method_name(fname)])
  end


  def compile_module(scope,name, *exps)
    # FIXME: This is a cop-out that will cause horrible
    # crashes - they are not the same (though nearly)
    compile_class(scope,name, *exps)
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
        lscope
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

    # Find the enclosing ClassScope for klass_size
    class_scope = find_class_scope(scope)

    # Using nested let()'s for clean scope management
    # Outer let: evaluate expr and save to __eigenclass_obj
    let(scope, :__eigenclass_obj) do |outer_scope|
      # Evaluate and assign the object expression to __eigenclass_obj
      compile_eval_arg(outer_scope, [:assign, :__eigenclass_obj, expr])

      # Inner let: create eigenclass and assign to :self
      let(outer_scope, :self) do |lscope|
        # Mark this LocalVarScope as an eigenclass scope
        # This is checked in compile_defm (compile_class.rb:16) to handle method definitions
        lscope.eigenclass_scope = true

        # Create the eigenclass using manual assembly (since __new_class_object is a C function)
        # First, get __eigenclass_obj into %eax
        obj_val = compile_eval_arg(lscope, :__eigenclass_obj)
        @e.save_result(obj_val)

        # Get obj's class (obj[0]) to use as eigenclass superclass
        @e.movl("(%eax)", :edx)  # Load obj[0] (obj's current class) into %edx

        # Call __new_class_object(size, superclass, ssize, classob)
        @e.pushl("$0")  # classob = 0 (will default to Class in the constructor)
        @e.pushl("$#{class_scope.klass_size}")  # ssize
        @e.pushl(:edx)  # superclass = obj[0] (obj's current class)
        @e.pushl("$#{class_scope.klass_size}")  # size
        @e.call("__new_class_object")
        @e.addl("$16", :esp)  # Clean up 4 arguments
        # Result: eigenclass now in %eax

        # Save eigenclass to :self local variable
        # Get the offset for :self from the LocalVarScope
        self_lvar = lscope.get_arg(:self)
        @e.save_to_local_var(:eax, self_lvar[1])

        # Assign eigenclass to obj[0]
        compile_eval_arg(lscope, [:assign, [:index, :__eigenclass_obj, 0], :self])

        # Set eigenclass name
        compile_eval_arg(lscope, [:assign, [:index, :self, 2], "<#{class_scope.local_name.to_s} eigenclass>"])

        # Compile eigenclass body
        compile_ary_do(lscope, exps)

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
    cscope = scope.find_constant(name)

    if name.is_a?(Array)
      return compile_eigenclass(scope, name[-1], *exps)
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
