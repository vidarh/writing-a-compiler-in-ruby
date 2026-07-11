# frozen_string_literal: true

class Compiler

  # Compiles a method definition and updates the
  # class vtable.
  def compile_defm(scope, name, args, body)
    orig_scope = scope
    scope = scope.class_scope

    if name.is_a?(Array)
      # Singleton def `def recv.name`: the receiver (name[0]) is evaluated in the ENCLOSING scope, which
      # may hold locals or a closure __env__ (e.g. `obj = Object.new; def obj.to_i; ...` inside a block).
      # Use orig_scope, not the class_scope narrowed above -- otherwise a receiver rewritten to
      # [:index, __env__, n] cannot resolve __env__ and is miscompiled as a method call.
      compile_eigenclass(orig_scope, name[0], [[:defm, name[1], args, body]])
      return Value.new([:subexpr])
    end

    # FIXME: Replace "__closure__" with the block argument name if one is present
    f = Function.new(name,[:self,:__closure__]+args, body, scope, @e.get_local) # "self" is "faked" as an argument to class methods

    cleaned = clean_method_name(name)
    fname = "__method_#{scope.name}_#{cleaned}"
    fname = @global_functions.set(fname, f)

    # Register method in vtable (offsets are global, same for all classes)
    scope.set_vtable_entry(name, fname, f)
    v = scope.vtable[name]

    # Install the method at runtime on the def's target. A bare `def` in a class body / at top level targets
    # the lexical class/Object (resolved via class_scope). Inside a real block (a FuncScope in the chain)
    # the def belongs to the block's RUNTIME self, whatever it is: for class_eval/Class.new-do that self is
    # the target class, for instance_eval it is an ordinary object. `self.__def_target` dispatches on the
    # type -- Class/Module return self (install an instance method), any other object returns its singleton
    # class (install a singleton method) -- so `self` itself never changes. (`:self` here resolves in
    # orig_scope, which inside a block is [:arg,0], the block's runtime receiver.)
    if scope_has_funcscope?(orig_scope)
      # Block-def: installed on a runtime-determined class, so super in its body must use the runtime
      # self.class.superclass path rather than the lexical (wrong) class_scope name.
      f.block_def = true
      compile_eval_arg(orig_scope,
        [:let, [:__deftgt],
          [:assign, :__deftgt, [:callm, :self, :__def_target]],
          [:sexp, [:call, :__set_vtable, [:__deftgt, v.offset, fname.to_sym]]]])
    else
      compile_eval_arg(scope, [:sexp, [:call, :__set_vtable, [:self, v.offset, fname.to_sym]]])
    end

    # A `def` is an expression: in Ruby it evaluates to the defined method's name as a Symbol, e.g.
    # `x = def foo; end` sets x = :foo. The install above otherwise leaves __set_vtable's return -- the
    # raw method address -- which crashed when a def used in value position was then sent a message
    # (`(def some_method; end).should == :some_method`). Emit the name symbol as the result, but ONLY
    # when it is already interned (the program mentions `:name` as a literal, registered by
    # rewrite_symbol_constant) so no new symbol is registered here -- registering every method name
    # ballooned the startup symbol init. A def whose value is actually inspected is virtually always
    # compared against its own `:name` literal, so the interned check covers the real cases.
    if @symbols.member?(name.to_s)
      compile_eval_arg(scope, [:sexp, symbol_name(name.to_s)])
    end

    # This is taken from compile_defun - it does not necessarily make sense for defm
    return Value.new([:subexpr])
  end

  # True when `scope`'s chain reaches a FuncScope before its enclosing class/module scope: the def is
  # lexically inside a block/method body, so its `self` is that scope's runtime receiver ([:arg,0]) rather
  # than the lexical class. (A class-body def hits a ModuleScope first; a top-level def has none.)
  def scope_has_funcscope?(scope)
    s = scope
    while s
      return true  if s.is_a?(FuncScope)
      return false if s.is_a?(ModuleScope)
      s = s.respond_to?(:next) ? s.next : nil
    end
    false
  end

  # True when `scope` is inside an escaped s-expression (%s(...)): compile_sexp wraps the scope in a
  # SexpScope. Used to keep raw sexp `(call var ...)` as a genuine indirect call while Ruby-level
  # `name(...)` always dispatches the method (see compile_call).
  def scope_has_sexpscope?(scope)
    s = scope
    while s
      return true if s.is_a?(SexpScope)
      s = s.respond_to?(:next) ? s.next : nil
    end
    false
  end


  def compile_module(scope,name, *exps)
    # FIXME: This is a cop-out that will cause horrible
    # crashes - they are not the same (though nearly)
    compile_class(scope,name, *exps)
  end

  # True if `target` is reachable from `start` by following the namespace (next) chain.
  def scope_in_chain?(start, target)
    cur = start
    while cur
      return true if cur == target
      cur = cur.respond_to?(:next) ? cur.next : nil
    end
    false
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
  # `undef name, ...` removes method definitions. STUB: compiles to nothing -- it does not
  # yet actually remove the methods. A proper implementation would point each name's vtable
  # slot at the method_missing thunk (cf. __alias_method_runtime in lib/core/class.rb).
  def compile_undef(scope, *names)
    return Value.new([:subexpr])
  end

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

    # Generate runtime code to copy the function pointer from old to new offset.
    # This uses __alias_method_runtime which just does: vtable[new_off] = vtable[old_off].
    # As with `def` (see compile_defm), an alias inside a block targets the block's RUNTIME
    # self: for class_eval/Class.new-do that self is the target class, but for instance_eval it
    # is an ordinary object whose singleton class should receive the alias. Routing through
    # `self.__def_target` (Class/Module return self; any other object returns its singleton
    # class) makes both cases correct -- without it, instance_eval passes the object itself as
    # the vtable and __set_vtable walks its instance-var slots as a subclass list -> crash.
    if scope_has_funcscope?(scope)
      compile_eval_arg(scope,
        [:let, [:__aliastgt],
          [:assign, :__aliastgt, [:callm, :self, :__def_target]],
          [:sexp, [:call, :__alias_method_runtime, [:__aliastgt, new_entry.offset, old_entry.offset]]]])
    else
      compile_eval_arg(scope, [:sexp, [:call, :__alias_method_runtime, [:self, new_entry.offset, old_entry.offset]]])
    end

    return Value.new([:subexpr])
  end

  def mk_new_class_object(*args)
    [:sexp, [:call, :__new_class_object, args]]
  end

  def mk_class(ob)
    [:index,ob,0]
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

    # Eigenclasses are Class objects, so they must be sized to the FINAL runtime __vtable_size -- NOT a
    # compile-time klass_size / @vtableoffsets.max snapshot (which is smaller once later methods allocate
    # higher offsets). An under-sized eigenclass is read past its end by __include_module /
    # instance_methods / __alias_method_runtime (they iterate to __vtable_size) -- a heap OOB that crashes
    # flakily under ASLR. Use the link-time :__vtable_size symbol, matching Object#singleton_class and the
    # compile_class allocation path.
    eksize = :__vtable_size

    # Using nested let()'s for clean scope management
    # Outer let: evaluate expr and save to __eigenclass_obj
    unique_id = @e.get_local[2..-1]
    @e.comment(Emitter::COMMENTS && "Eigenclass #{unique_id}")

    # The metaclass (the eigenclass's def-time `self`) is stored in a UNIQUE GLOBAL, not a local.
    # A local named :self is forced into %esi (the self-register) by the register allocator; %esi is
    # caller-saved and reloaded from the GLOBAL self by reload_self after every call, so the metaclass
    # parked there is destroyed by the __set_vtable calls that install this eigenclass's methods, and
    # the stale %esi then gets spilled back into the slot -> heap smash (KNOWN_ISSUES #8). A plain
    # stack local is also unsafe (its slot can collide with those calls' outgoing-argument area). A
    # global is immune to both. Per-eigenclass (unique_id) so nested eigenclasses don't clash.
    # A $-prefixed global auto-registers and is assigned/read through the normal machinery (unlike a
    # bare [:global, name], which is not a valid assignment lvalue). ec_self is used as an ordinary
    # variable reference everywhere below. NB: build the symbol with string interpolation + .to_sym,
    # NOT a `:"...#{unique_id}..."` symbol literal -- the self-hosted compiler does not interpolate
    # inside symbol literals (it emits the literal text "{unique_id}"), which breaks selftest-c.
    ec_self = "$__ec_self__#{unique_id}".to_sym

    let(scope, :__eigenclass_obj) do |outer_scope|

      compile_eval_arg(outer_scope, [:assign, :__eigenclass_obj, expr])

      # `class << 1` (a tagged Integer immediate) would have its "slots" indexed/written through the
      # tag below -- a wild pointer access -> SIGSEGV -- and MRI does not give Integer/Symbol
      # receivers singleton classes at all: it raises TypeError. Guard with RAW checks (a bit-0 tag
      # test, and a slot-0 class-pointer compare against Symbol) so the happy path stays dispatch-free:
      # core-library eigenclasses run during startup, before Object's method defs are installed, so a
      # method call here would hit an empty vtable. The raising helper is only dispatched on the
      # failure path, which only user code can reach.
      compile_eval_arg(outer_scope, [:sexp, [:if, [:ne, [:bitand, :__eigenclass_obj, 1], 0],
        [:callm, :self, :__raise_singleton_type_error, []]]])
      compile_eval_arg(outer_scope, [:sexp, [:if, [:eq, [:index, :__eigenclass_obj, 0], :Symbol],
        [:callm, :self, :__raise_singleton_type_error, []]]])

      # REUSE an existing eigenclass rather than wrapping it in a new one. Each `def self.x` /
      # `class << obj` used to create a FRESH metaclass whose superclass was the object's previous
      # slot-0 -- so a class with two singleton defs got a CHAIN of eigenclasses (ec_bar -> ec_foo
      # -> real class). `super` in a class method resolves at runtime via self.class.superclass;
      # with the chain, that landed on the SIBLING eigenclass (holding the very method being
      # super'd from) instead of the superclass's eigenclass -> infinite recursion
      # (language/super_spec: B.bar -> super -> A.bar -> foo -> B.foo -> super looped forever).
      #
      # Detection is by the INHERITANCE CHAIN: for a CLASS receiver, slot 0 is either Class itself
      # (no eigenclass yet) or an eigenclass -- whose superclass chain contains Class, because an
      # eigenclass-of-a-class is created with `superclass = the class's previous slot 0`, which
      # bottoms out at Class. An ordinary class's ANCESTRY never contains Class (Class is its
      # class, not its ancestor), so for a plain-object receiver the walk finds nothing and we
      # create as before (plain objects' repeated singleton defs still chain -- they have no
      # structural discriminator, which is why MRI carries an FL_SINGLETON flag).
      # The walk reads raw slot-3 links; chains terminate at 0 (the bootstrap classes' root).
      #
      # The chain test alone is NOT sufficient: class creation copies classob from the superclass
      # (`classob = superclass[0]` in compile_class), so a subclass of a class that already has an
      # eigenclass INHERITS that eigenclass as its slot 0 -- the walk finds Class in its chain even
      # though it belongs to the superclass. Reusing it would install the subclass's singleton
      # methods into the SUPERCLASS's metaclass (clobbering its methods, and making super from
      # there skip to Class). So additionally require OWNERSHIP: the eigenclass's superclass must
      # be exactly the class of obj's superclass (obj[0][3] == obj[3][0]) -- that is precisely what
      # creation set it to (ec.superclass = obj's previous slot 0 = classob copied from obj[3]).
      # An inherited pointer fails this: it IS obj[3][0], and no class is its own superclass.
      # obj[3] is only dereferenced after the chain walk proved obj is a class (and guarded
      # non-zero for the bootstrap root).
      #
      # Creation path notes (unchanged semantics):
      # - @instance_size (slot 1) is inherited from the base class: __new_class_object only copies
      #   vtable slots >= 6, so it would stay 0 otherwise and instances allocated through the
      #   singleton class would be zero-slot -> heap overflow on ivar writes.
      # - slot 3 holds the superclass (the object's original class), set by __new_class_object.
      # The walk runs in raw sexp (let-locals, raw slot reads) and RETURNS the existing eigenclass
      # or 0; the result lands in ec_self via a normal Ruby-level assign ($-globals resolve through
      # the normal machinery, not inside raw sexp). Creation below stays the original Ruby-level
      # statement sequence, now conditional on that result.
      compile_eval_arg(outer_scope, [:assign, ec_self,
        [:sexp, [:let, [:eck, :ecfound],
          [:assign, :ecfound, 0],
          [:assign, :eck, [:index, :__eigenclass_obj, 0]],
          [:if, [:ne, :eck, :Class],
            [:while, [:ne, :eck, 0],
              [:do,
                [:if, [:eq, :eck, :Class],
                  [:do, [:assign, :ecfound, 1], [:assign, :eck, 0]],
                  [:assign, :eck, [:index, :eck, 3]]]]]],
          [:if, [:ne, :ecfound, 0],
            [:if, [:ne, [:index, :__eigenclass_obj, 3], 0],
              [:if, [:eq, [:index, [:index, :__eigenclass_obj, 0], 3],
                          [:index, [:index, :__eigenclass_obj, 3], 0]],
                [:index, :__eigenclass_obj, 0],
                0],
              0],
            0]]]])

      compile_eval_arg(outer_scope, [:if, ec_self, 0,
        [:do,
          [:assign, ec_self,
            mk_new_class_object(
              eksize,                                # size = Class's klass_size
              [:index, :__eigenclass_obj, 0],        # superclass = obj.class
              eksize,                                # ssize = Class's klass_size
              0                                      # classob = 0 (defaults to Class)
            )],
          [:assign, [:index, :__eigenclass_obj, 0], ec_self],
          [:assign, [:index, ec_self, 1], [:index, [:index, ec_self, 3], 1]],
          [:assign, [:index, ec_self, 2], "Eigenclass_#{unique_id}"]]])

      escope = EigenclassScope.new(outer_scope, "Eigenclass_#{unique_id}", @vtableoffsets, class_scope)
      escope.self_global = ec_self

      # Compile eigenclass body. Method defs resolve def-time `self` to the metaclass global via
      # EigenclassScope#get_arg, so their __set_vtable installs land on the metaclass.
      #
      # A closure created directly in the eigenclass body (`class << obj; l = -> {...}; end`) needs an
      # __env__/__closure__/__tmp_proc to reference, exactly like a class body (see compile_class's
      # closure branch): the transformed body contains the full proc-creation machinery, and compiling
      # it without these in scope emitted references to unresolvable names -> garbage proc @addr ->
      # SIGSEGV on call. Also declare the body's own locals so they persist across statements.
      body_locals = class_body_locals(exps)
      if class_body_creates_closure?(exps)
        let(escope, :__env__, :__closure__, :__tmp_proc, *body_locals) do |lscope|
          compile_eval_arg(lscope, [:sexp, [:assign, :__closure__, 0]])
          env_slots = [2, class_body_env_size(exps) + 1].max
          compile_eval_arg(lscope, [:sexp, [:assign, :__env__, [:call, :__alloc_env, env_slots]]])
          exps.each do |e|
            compile_do(lscope, e)
          end
        end
      elsif !body_locals.empty?
        let(escope, *body_locals) do |lscope|
          exps.each do |e|
            compile_do(lscope, e)
          end
        end
      else
        exps.each do |e|
          compile_do(escope, e)
        end
      end

      # Return the eigenclass (the metaclass)
      compile_eval_arg(outer_scope, ec_self)
    end

    @e.comment("=== Eigenclass end")
    return Value.new([:subexpr], :object)
  end


  # Compiles a class definition.
  # Takes the current scope, the name of the class as well as a list of expressions
  # that belong to the class.
  def compile_class(scope, name,superclass, *exps)
    superc = name == :Class ? nil : @classes[superclass]
    # If not found, try qualified name within current scope
    if !superc && name != :Class && superclass.is_a?(Symbol) && scope.respond_to?(:name) && !scope.name.empty?
      superc = @classes["#{scope.name}__#{superclass}".to_sym]
    end

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
        # A runtime-expression child (non-symbol) gets a placeholder so the file still compiles.
        parts.unshift(n[2].is_a?(Symbol) ? n[2] : :__dynamic__)
        n = n[1]
      end
      # Parent may be a runtime expression (e.g. module m::N where m is a captured variable,
      # parsed as [:index, :__env__, N]). We can't nest into a runtime module statically, so
      # fall back to a flattened placeholder namespace -- it compiles (runtime nesting is not
      # honoured) rather than failing the whole file.
      n = :__dynamic__ unless n.is_a?(Symbol)
      parts.unshift(n)
      # Flatten to Foo__Bar__Baz for the class name
      name = parts.join("__").to_sym
      # For tracking parent scope, use first part as nested_parent, rest as nested_child
      # This is simplified - we're effectively creating a flat namespace
      nested_parent = parts[0..-2].join("__").to_sym if parts.length > 1
      nested_child = parts.last if parts.length > 1
      # Mark that we used explicit namespace syntax - don't add parent prefix
      explicit_namespace = true
    end

    # Determine the parent scope for this class definition
    # If force_global (class ::A), always use global scope
    # For explicit namespace (class Foo::Bar from outside Foo), look up Foo as parent
    # Otherwise walk scope chain to find ModuleScope/ClassScope, but if we hit GlobalScope first, use it
    if force_global
      parent_scope = @global_scope
    elsif explicit_namespace && nested_parent
      # For class Foo::Bar defined outside Foo, look up Foo as the parent scope
      # If the parent doesn't exist yet, fall back to walking the scope chain
      # (This handles cases like `class nil::Foo` which should fail at runtime, not compile time)
      parent_scope = @classes[nested_parent]
      if !parent_scope
        # Parent not found in @classes - fall back to scope chain lookup
        parent_scope = scope
        while parent_scope && !parent_scope.is_a?(ModuleScope) && parent_scope != @global_scope
          parent_scope = parent_scope.next
        end
        parent_scope ||= @global_scope
      end
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
    # If parent is GlobalScope or Object (default parent), use just the name (e.g., "Bar")
    # We skip Object prefix because classes/modules defined in lambdas/methods land in
    # Object scope but should be global constants, not Object__Foo
    if explicit_namespace
      if name.to_s.start_with?("self__") && parent_scope.is_a?(ModuleScope) && parent_scope.name != "Object"
        # A DYNAMIC deref name (`module self::B`) flattens to "self__B" -- not a real global path, so
        # the usual "explicit namespace means the name is already fully qualified" rule is wrong for
        # it. The transform (build_class_scopes) registers such a nested module WITH the enclosing
        # scope prefix ("self__A__self__B"); deriving the bare "self__B" here made compile-time use a
        # DIFFERENT global cell than the one the registered scope's metadata writes resolve to -- the
        # class object was created in one cell and its instance_size/name written through the other
        # (never-assigned, null) cell -> SIGSEGV on `module self::B` nested inside `module self::A`.
        fully_qualified_name = "#{parent_scope.name}__#{name}".to_sym
      else
        # Name already contains full path (e.g., ClassSpecs__L), don't add prefix
        fully_qualified_name = name.to_sym
      end
    elsif parent_scope.is_a?(ModuleScope) && parent_scope.name != "Object"
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
      # When explicit_namespace is true (class Foo::Bar syntax), name contains the full path
      # but ClassScope.name will add parent prefix, so extract just the child name
      # Example: name="ClassSpecs__L", parent=ClassSpecs => use local_name="L"
      # to avoid double prefix (ClassSpecs__ClassSpecs__L)
      # HOWEVER: Only use nested_child if parent_scope is actually the parent module!
      # If parent_scope doesn't match nested_parent (e.g., class ClassSpecs::Number::MyClass
      # where parent_scope falls back to Object), use the full name and @global_scope
      # to avoid Object__MyClass
      use_nested_child = explicit_namespace && nested_child &&
                         parent_scope.is_a?(ModuleScope) &&
                         parent_scope.name == nested_parent.to_s
      local_name = use_nested_child ? nested_child : name
      # When explicit namespace but parent doesn't match, use @global_scope to avoid wrong prefix
      # UNLESS parent is a real ModuleScope (not Object), in which case use it for prefix
      scope_for_class = if use_nested_child
        parent_scope
      elsif parent_scope.is_a?(ModuleScope) && parent_scope.name != "Object" && parent_scope != @global_scope
        # Parent is a real module/class (including eigenclasses), use it for prefix
        parent_scope
      else
        @global_scope
      end
      cscope = ClassScope.new(scope_for_class, local_name, @vtableoffsets, superc, local_scope)
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
      # ...but not when the enclosing scope is itself inside cscope (e.g. reopening via
      # module ::M from within M): that would make cscope.local_scope chain back to cscope
      # and send get_arg into infinite recursion.
      cscope.local_scope = local_scope if local_scope && !scope_in_chain?(local_scope, cscope)
    end

    # For nested class/module Foo::Bar, register Bar in Foo's namespace
    # This must happen outside the !cscope check because modules are created by transform phase
    if nested_parent && nested_child
      parent_module = @global_scope.find_constant(nested_parent)
      if parent_module && parent_module.respond_to?(:add_constant)
        parent_module.add_constant(nested_child, cscope)
      end
    end

    @e.comment(Emitter::COMMENTS && "=== class #{cscope.name} ===")


    @e.evict_regs_for(:self)


    # Use the fully qualified name for global constant tracking and class object creation
    # But when we're inside a module scope, use the simple name for get_arg (the module will add prefix)
    # When we're in global scope or using explicit namespace from outside the module, use fq_name
    fq_name = fully_qualified_name.to_sym

    # Determine which name to use in the assignment based on the scope context
    # If parent_scope is a real ModuleScope (not Object) and we're not using explicit namespace,
    # use the simple name so the module's get_arg adds the prefix correctly
    # But if parent is Object, always use fq_name to avoid Object__ prefix
    assign_name = if parent_scope.is_a?(ModuleScope) && parent_scope.name != "Object" && parent_scope != @global_scope && !explicit_namespace
      # Inside a real module (not Object), use simple name (e.g., :L not :ClassSpecs__L)
      cscope.local_name.to_sym
    else
      # Global scope, Object parent, or explicit namespace: use fully qualified name
      fq_name
    end

    # The check for :Class and :Kernel is an "evil" temporary hack to work around the bootstrapping
    # issue of creating these class objects before Object is initialized. A better solution (to avoid
    # demanding an explicit order would be to clear the Object constant and make sure __new_class_object
    #does not try to deref a null pointer
    #
    sscope = (fq_name == superclass or fq_name == :Class or fq_name == :Kernel) ? nil : @classes[superclass]
    # If not found, try qualified name within current scope
    if !sscope && superclass.is_a?(Symbol) && scope.respond_to?(:name) && !scope.name.empty?
      sscope = @classes["#{scope.name}__#{superclass}".to_sym]
    end

    # ssize = number of vtable slots __new_class_object copies from the superclass; class_alloc_size = the
    # size of the new class object itself. For a compile-time-known superclass, use its klass_size. For a
    # superclass known only at RUNTIME (`class Sub < A` where `A = Class.new`), sscope is nil: copying 0
    # slots left Sub's whole vtable as method_missing thunks, so `Sub.new` -> missing `initialize` ->
    # method_missing thunk -> method_missing forever (hang). Copy the superclass's FULL runtime vtable and
    # size the object to match (both must be the runtime __vtable_size, not the smaller compile-time
    # klass_size, or the copy loop overruns the object). This applies only to a genuine user-constant
    # runtime superclass -- :Object/:Class/:Kernel with a nil sscope are the bootstrap case and keep ssize 0.
    # A superclass given as a lowercase-initial symbol (`class Foo < parent`) is a LOCAL variable or
    # method call, never a constant (constants are Capitalised). It must be EVALUATED at runtime -- read
    # the local / call the method -- not referenced as a static global symbol `$parent` (which mis-resolves
    # to Object at top level and emits an undefined symbol inside a block -> link error; KNOWN_ISSUES 3h).
    # Route it through the same __superclass__ expression path used for `class Sub < Class.new`. This is a
    # no-op for every other superclass form (constant / absent / expression). Test the first char with
    # STRING comparison on a 1-char substring: works under both MRI (`to_s[0]` is a char) and self-hosted
    # (`to_s[0]` is a byte), and avoids `=~ /regex/` which the self-hosted parser mis-reads as division.
    local_super = false
    if superclass.is_a?(Symbol)
      sc_first = superclass.to_s[0, 1]
      local_super = (sc_first >= "a" && sc_first <= "z") || sc_first == "_"
    end
    runtime_super = !sscope && superclass.is_a?(Symbol) && !local_super &&
      ![:Object, :Class, :Kernel].include?(superclass) && fq_name != superclass
    # A superclass given as an EXPRESSION (`class Sub < Struct.new(:a)` / `class Sub < Class.new`) is only
    # known at runtime too. It is evaluated into __superclass__ (see the superclass.is_a?(Array) branch
    # below), so it needs the same full-vtable copy as runtime_super. Otherwise ssize stays 0, __new_class_
    # object copies no methods, and every call -- including method_missing itself -- lands on a
    # method_missing thunk that recurses forever (hang).
    expr_super = !sscope && (superclass.is_a?(Array) || local_super)
    if sscope
      ssize = sscope.klass_size
      # Allocate the class object with the FINAL runtime __vtable_size, not the compile-time
      # cscope.klass_size (which is @vtableoffsets.max evaluated mid-codegen and can be SMALLER than the
      # link-time __vtable_size once later methods allocate higher offsets). __include_module and other
      # code iterate a class object up to __vtable_size, so a klass_size-sized object gets read (and
      # occasionally written) one-or-more slots PAST its end -- a heap OOB that crashes flakily under
      # ASLR when the slot lands in an unmapped page. The extra slots [klass_size, __vtable_size) are
      # filled with base_vtable method_missing thunks, so this only fixes the size; behaviour is unchanged.
      class_alloc_size = :__vtable_size
    elsif runtime_super || expr_super
      ssize = :__vtable_size
      class_alloc_size = :__vtable_size
    else
      ssize = 0
      class_alloc_size = :__vtable_size
    end

    # Metaclass (slot 0). Share the superclass's metaclass so class methods are inherited: a known
    # non-Object superclass by name, or a runtime-only superclass via its slot 0. Plain Class otherwise.
    classob = :Class
    if superc && superc.name != "Object"
      classob = [:index, superc.name.to_sym , 0]
    elsif runtime_super
      classob = [:index, superclass, 0]
    elsif expr_super
      classob = [:index, :__superclass__, 0]
    end

    # When using explicit namespace (class Foo::Bar from outside Foo),
    # the constant check/assignment must use global scope to avoid incorrect prefixing
    # Otherwise scope.get_arg can't find Foo__Bar and adds the current scope prefix
    #
    # When parent_scope is Object (the default parent), use @global_scope to avoid
    # adding "Object__" prefix to all classes/modules defined in lambdas/methods.
    # This happens because when we walk the scope chain from inside a lambda, we skip
    # FuncScope/LocalVarScope and land on Object as the nearest ModuleScope.
    #
    # However, we still need to use the original scope for evaluating the superclass
    # expression, as it might reference closure variables.
    use_global_for_object = parent_scope.is_a?(ModuleScope) && parent_scope.name == "Object"

    # If superclass is an expression (not a simple symbol/constant), wrap the class creation
    # in a let block to evaluate the superclass first. This avoids SexpScope converting
    # method calls to function calls.
    if superclass.is_a?(Array) || local_super
      # Superclass is an expression or a runtime local/method (class Foo < parent) - evaluate it in a let
      # block. This allows method calls like remove_const(:Foo) and local-variable superclasses to work,
      # reading the value with a normal assign (outside the sexp) rather than a static symbol reference.
      let(scope, :__superclass__) do |let_scope|
        compile_eval_arg(let_scope, [:assign, :__superclass__, superclass])

        if use_global_for_object || explicit_namespace
          compile_eval_arg(let_scope, [:sexp,
                                   [:if,
                                    [:eq, fq_name, 0],
                                    [:assign, fq_name,
                                     [:call, :__new_class_object, [class_alloc_size, :__superclass__, ssize, classob]]
                                    ]]])
        else
          compile_eval_arg(let_scope, [:if,
                                   [:sexp,[:eq, assign_name, 0]],
                                   [:assign, assign_name,
                                    mk_new_class_object(class_alloc_size, :__superclass__, ssize, classob)
                                   ]])
        end
      end
    else
      # Simple superclass (symbol or nil) - use directly
      if use_global_for_object || explicit_namespace
        compile_eval_arg(scope, [:sexp,
                                 [:if,
                                  [:eq, fq_name, 0],
                                  [:assign, fq_name,
                                   [:call, :__new_class_object, [class_alloc_size, superclass, ssize, classob]]
                                  ]]])
      else
        compile_eval_arg(scope, [:if,
                                 [:sexp,[:eq, assign_name, 0]],
                                 [:assign, assign_name,
                                  mk_new_class_object(class_alloc_size, superclass, ssize, classob)
                                 ]])
      end
    end

    # Reopening a constant that does not hold a class/module (`B = 1; module B; end`) used to fall
    # through to the machinery below, which writes the class object's metadata slots: on a tagged
    # immediate that is a wild write (SIGSEGV -- language/module_spec died here), on nil/true/false/
    # String it silently corrupts the shared object. MRI raises TypeError. Detect structurally, with
    # a dispatch-free happy path (this runs for every class statement, including bootstrap before
    # Object's methods are installed): a genuine class/module object's slot-0 chain reaches Class --
    # the same walk as compile_eigenclass; modules qualify since their classob is Class. Skip the
    # check while the Class global is still 0 (bootstrap roots created before Class itself). The
    # raising helper only dispatches on the failure path, which only user code can reach.
    ct = (use_global_for_object || explicit_namespace) ? fq_name : assign_name
    compile_eval_arg(scope, [:sexp, [:let, [:ck, :okc],
      [:assign, :okc, 0],
      [:if, [:eq, :Class, 0],
        [:assign, :okc, 1],
        [:if, [:eq, [:bitand, ct, 1], 0],
          [:do,
            [:assign, :ck, [:index, ct, 0]],
            # slot 0 == 0 is a bootstrap root created before the Class global existed (its classob
            # is fixed up later); user constants can never hold such an object, so accept it.
            [:if, [:eq, :ck, 0], [:assign, :okc, 1]],
            [:while, [:ne, :ck, 0],
              [:do,
                [:if, [:eq, :ck, :Class],
                  [:do, [:assign, :okc, 1], [:assign, :ck, 0]],
                  [:assign, :ck, [:index, :ck, 3]]]]]]]],
      [:if, [:eq, :okc, 0], [:callm, ct, :__raise_reopen_type_error, []]]]])

    @global_constants << fq_name

    # In the context of "cscope", "self" refers to the Class object of the newly instantiated class.
    # Previously we used "@instance_size" directly instead of [:index, :self, 1], but when fixing instance
    # variable handling and adding offsets to avoid overwriting instance variables in the superclass,
    # this broke, as obviously we should not be able to directly mess with the superclass's instance
    # variables, so we're intentionally violating encapsulation here.

    # For a superclass known only at RUNTIME (`class Sub < A` where A = Class.new(...), or an expression
    # superclass), the compile-time cscope has no @superclass, so cscope.instance_size counts only Sub's own
    # ivars and OMITS the ivars the superclass adds (e.g. a Struct subclass's @__struct_values). An instance
    # allocated with that too-small size is then corrupted when an inherited method writes an inherited ivar
    # slot. Take the larger of the compile-time size and the runtime superclass's instance_size. We read the
    # superclass via self's slot 3 (set by __new_class_object) so this works whether the superclass came in
    # as a symbol or an expression.
    if runtime_super || expr_super
      compile_exp(cscope, [:assign, [:index, :self, 1],
                           [:if, [:lt, cscope.instance_size, [:index, [:index, :self, 3], 1]],
                            [:index, [:index, :self, 3], 1],
                            cscope.instance_size]])
    else
      compile_exp(cscope, [:assign, [:index, :self, 1], cscope.instance_size])
    end

    # We need to store the "raw" name here, rather than a String object,
    # as String may not have been initialized yet
    compile_exp(cscope, [:assign, [:index, :self, 2], fq_name.to_s])

    # Set up %esi to point to the class object so method calls in class body work
    # Without this, calls like `private :method_name` fail because %esi isn't set
    reload_self(cscope)

    # Local variables assigned at the top level of the body must persist across the body's statements
    # (e.g. `m = Module.new{..}; C = m.instance_method(:foo)`). Each statement is otherwise its own
    # compile unit, so without a shared LocalVarScope a later bare `m` compiles as `self.m` (a method
    # call on the class) -> NoMethodError. Declare them in the `let` that wraps the body.
    body_locals = class_body_locals(exps)

    if class_body_creates_closure?(exps)
      # A closure created directly in the class body needs an __env__ to reference (class bodies are
      # their own compile unit, so an outer/top-level __env__ is out of scope -> it resolves to the class
      # object and the closure prologue corrupts it). Allocate one in a LocalVarScope (the `let` helper,
      # as compile_eigenclass uses, manages self/scope properly). __alloc_env and __new_proc are low-level
      # calls that clobber %esi, so reload self before EACH statement (a class body's self lives in %esi,
      # set once -- unlike a method's reloadable stack-arg self).
      let(cscope, :__env__, :__closure__, :__tmp_proc, *body_locals) do |lscope|
        compile_eval_arg(lscope, [:sexp, [:assign, :__closure__, 0]])
        # The env must be sized to hold every slot the transform assigned, not a fixed 2. A class body
        # whose closures capture several class-body locals gets `(index __env__ N)` for N up to the number
        # of captured vars; allocating only 2 slots let those writes run off the end of the heap block and
        # corrupt adjacent malloc metadata. Size it from the highest __env__ index actually used (matching
        # the top-level closure path in transform.rb, which sizes its own __alloc_env the same way).
        env_slots = [2, class_body_env_size(exps) + 1].max
        compile_eval_arg(lscope, [:sexp, [:assign, :__env__, [:call, :__alloc_env, env_slots]]])
        exps.each do |e|
          stmts = e.is_a?(Array) ? e : [e]
          stmts.each do |stmt|
            reload_self(lscope)
            compile_do(lscope, stmt)
          end
        end
      end
    elsif !body_locals.empty?
      let(cscope, *body_locals) do |lscope|
        reload_self(lscope)
        exps.each do |e|
          addr = compile_do(lscope, *e)
        end
      end
    else
      exps.each do |e|
        addr = compile_do(cscope, *e)
      end
    end

    @e.comment(Emitter::COMMENTS && "=== end class #{fq_name} ===")
    return Value.new([:global, fq_name], :object)
  end

  # True if any statement in a class/module body DIRECTLY creates a closure (a `__new_proc` call not nested
  # inside a further class/module/method scope, which would carry its own __env__).
  def class_body_creates_closure?(exps)
    found = false
    walk = lambda do |n|
      return if found || !n.is_a?(Array)
      return if [:class, :module, :defm, :defun].include?(n[0])
      if n[0] == :call && n[1] == :__new_proc
        found = true
        return
      end
      n.each { |c| walk.call(c) }
    end
    exps.each { |e| walk.call(e) }
    found
  end

  # Collect the local variables ASSIGNED at the top level of a class/module body (so they can be
  # declared in a shared LocalVarScope wrapping the body). Descends into control flow (if/while/case/
  # do) but stops at nested scope boundaries (defm/defun/class/module and any block/proc/lambda), whose
  # assignments are their own locals. Skips ivars (@x), globals ($x), constants (uppercase) and the
  # compiler's own __internal names.
  def class_body_locals(exps)
    locals = []
    collect = lambda do |n|
      return if !n.is_a?(Array)
      return if [:defm, :defun, :class, :module, :proc, :lambda, :block].include?(n[0])
      if n[0] == :assign && n[1].is_a?(Symbol)
        nm = n[1].to_s
        c0 = nm[0]
        # Skip ivars (@x), globals ($x), constants (uppercase first letter) and __internal names.
        # Uses char-code comparisons rather than a regex (the self-hosted regexp engine is limited,
        # and this runs during every class/module compile).
        ok = c0 != ?@ && c0 != ?$ && !(c0 >= ?A && c0 <= ?Z) && !nm.start_with?("__")
        locals << n[1] if ok
      end
      n.each { |c| collect.call(c) }
    end
    exps.each { |e| collect.call(e) }
    locals.uniq
  end

  # Highest `[:index, :__env__, N]` slot used against the CLASS BODY's own __env__, so the body's
  # __alloc_env can be sized to fit. Shared closures (transform-produced :defun taking __env__ as a
  # param) reference the same env and are counted; a nested `[:let ...]` that RE-binds :__env__ starts
  # its own environment (it carries its own __alloc_env) and is skipped. Returns -1 if none is used.
  def class_body_env_size(exps)
    max = -1
    walk = lambda do |n|
      return if !n.is_a?(Array)
      # A nested let that rebinds __env__ owns a separate environment; don't descend into it.
      return if n[0] == :let && n[1].is_a?(Array) && n[1].include?(:__env__)
      if n[0] == :index && n[2].is_a?(Integer)
        # Count direct root-env refs AND hop-wrapped ones: a ref from a depth-d nested block
        # arrives as [:index, [:index, ... [:index, :__env__, 1] ...], k] (parent hops -- see
        # __env_hops in transform.rb). Unwrap the hop chain; if it bottoms out at :__env__ the
        # index targets a ROOT slot and must be covered by the allocation, or writes from deep
        # blocks land past the buffer (heap corruption -- selftest's String tests died in a
        # later calloc).
        t = n[1]
        while t.is_a?(Array) && t[0] == :index && t[2] == 1
          t = t[1]
        end
        max = n[2] if t == :__env__ && n[2] > max
      end
      n.each { |c| walk.call(c) }
    end
    exps.each { |e| walk.call(e) }
    max
  end

end
