# Guards `class X < <localvar>`: a superclass that is a LOCAL variable (or method call) must be evaluated
# at runtime, not referenced as a static global symbol -- which mis-resolved to Object at top level and
# emitted an undefined symbol inside a block (link error; KNOWN_ISSUES 3h). core/class/inherited_spec,
# language/class_spec, core/module/const_added_spec were COMPILE_FAIL because of this. The fix is a no-op
# for any other superclass form.
parent = Class.new do
  def greet; "from-parent"; end
end

class Child < parent
  def own; "own"; end
end
c = Child.new
p (Child.superclass == parent)   # true
p c.greet                        # "from-parent" (inherited from the local superclass)
p c.own                          # "own"

# Also inside a block (was a link error, not just wrong value):
made = nil
[1].each do
  made = Class.new(parent)
end
p (made.superclass == parent)    # true

# Normal constant superclass still works (unchanged path):
class Base2; def b; 1; end; end
class Sub2 < Base2; end
p Sub2.new.b                     # 1
p (Sub2.superclass == Base2)     # true
