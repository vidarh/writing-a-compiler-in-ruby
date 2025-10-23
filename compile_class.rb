
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
