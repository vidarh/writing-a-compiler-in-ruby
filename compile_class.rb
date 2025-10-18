
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
    @e.comment("=== Eigenclass start")

    # Find the enclosing ClassScope for klass_size
    class_scope = find_class_scope(scope)

    # Create the eigenclass
    # The eigenclass's superclass is obj.class
    # The eigenclass's class is Class
    # We need to create it and then assign it to obj[0]

    # Step 1: Create the eigenclass (result will be in %eax)
    superclass = mk_class(expr)  # obj[0]
    eigenclass_creation = mk_new_class_object(class_scope.klass_size, superclass, class_scope.klass_size, :Class)
    ret = compile_eval_arg(scope, eigenclass_creation)
    @e.save_result(ret)

    # Step 2: Store eigenclass to a temporary register so we don't lose it
    @e.pushl(:eax)

    # Step 3: Assign the eigenclass (from stack) to obj[0]
    @e.popl(:ecx)  # eigenclass now in %ecx
    obj_val = compile_eval_arg(scope, expr)  # load obj into %eax
    @e.save_result(obj_val)
    @e.movl(:ecx, "(%eax)")  # obj[0] = eigenclass

    # Step 4: Move eigenclass back to %eax for the let block
    @e.movl(:ecx, :eax)

    # Use a modified version of the `let` helper that supports eigenclass_scope marker
    # We inline it here to pass the eigenclass_scope parameter
    varlist = [:self]
    vars = Hash[*(varlist.zip(1..varlist.size)).flatten]
    lscope = LocalVarScope.new(vars, scope, true)  # true = eigenclass_scope marker

    @e.evict_regs_for(varlist)
    s = vars.size + 2
    @e.with_stack(s) do
      # Save eigenclass to local var - same as original let-based code
      @e.save_to_local_var(:eax, 1)

      # FIXME: Compiler @bug. Probably findvars again; see-also Compiler#let
      scope

      # Set eigenclass name
      compile_exp(lscope, [:sexp, [:assign, [:index, :self, 2], "<#{class_scope.local_name.to_s} eigenclass>"]])

      # Compile eigenclass body
      compile_ary_do(lscope, exps)

      # Load eigenclass back as return value
      @e.load_local_var(1)
    end
    @e.evict_regs_for(varlist)
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
