
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

    mscope = scope.find_constant(incl)
    if !mscope
      # Use position info from wrapping expression
      if pos
        raise CompilerError.new("Module not found: #{incl}", pos)
      else
        raise CompilerError.new("Module not found: #{incl}")
      end
    end
    scope.include_module(mscope)

    # 2. For each method, looks up method in current super class
    #    compares to current class vtable, and overwrites only
    #    if not matching.

    # (NOT IMPLEMENTED YET)

    # FIXME:
    # - Ensure we handle eigenclasses properly.
    # - Ensure *subsequent* changes are updated correctly.
    # - Dynamic constant lookups.

    Value.new([:subexpr])
  end
end
