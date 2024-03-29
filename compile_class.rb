
class Compiler

  # Compiles a method definition and updates the
  # class vtable.
  def compile_defm(scope, name, args, body)
    scope = scope.class_scope

    if name.is_a?(Array)
      compile_eigenclass(scope, name[0], [[:defm, name[1], args, body]])
      return Value.new([:subexpr])
    end


    # FIXME: Replace "__closure__" with the block argument name if one is present
    f = Function.new(name,[:self,:__closure__]+args, body, scope, @e.get_local) # "self" is "faked" as an argument to class methods

#    @e.comment("method #{name}")

    cleaned = clean_method_name(name)
    fname = "__method_#{scope.name}_#{cleaned}"
    fname = @global_functions.set(fname, f)
    scope.set_vtable_entry(name, fname, f)

    # Save to the vtable.
    v = scope.vtable[name]
    compile_eval_arg(scope,[:sexp, [:call, :__set_vtable, [:self,v.offset, fname.to_sym]]])
    
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

  def compile_eigenclass(scope, expr, exps)
    @e.comment("=== Eigenclass start")

    ob      = mk_class(expr)
    classob = mk_class(expr)
    ret = compile_eval_arg(scope, [:assign, ob,
                                   mk_new_class_object(scope.klass_size, ob, scope.klass_size, classob)
                                  ])
    @e.save_result(ret)

    let(scope,:self) do |lscope|
      @e.save_to_local_var(:eax, 1)
      # FIXME: Compiler @bug. Probably findvars again;
      # see-also Compiler#let
      scope
      # FIXME: This uses lexical scoping, which will be wrong in some contexts.
      compile_exp(lscope, [:sexp, [:assign, [:index, :self ,2], "<#{scope.local_name.to_s} eigenclass>"]])

      compile_ary_do(lscope, exps)
      @e.load_local_var(1)
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
