# Including a module into a class copies the module's methods into the class's vtable, and class objects
# are sized to the full runtime __vtable_size so __include_module never runs off the end. This exercises
# include + dispatch functionally (the size/OOB fix itself is ASLR-dependent, so it is validated by
# valgrind + the sweep crash count rather than a deterministic crash here). Verified vs MRI.
module M
  def mm; "from M"; end
end
class C
  include M
  def cc; "from C"; end
end
c = C.new
p(c.mm)   # "from M"
p(c.cc)   # "from C"

# include interleaved with method defs (methods at a range of vtable offsets)
module M2
  def m2; 42; end
end
class D
  def d1; 1; end
  include M2
  def d2; 2; end
end
d = D.new
p([d.d1, d.m2, d.d2])   # [1, 42, 2]

# first-defined-wins: a class method is NOT overwritten by an included module's same-named method
module Mn
  def nn; "module"; end
end
class F
  def nn; "class"; end
  include Mn
end
p(F.new.nn)   # "class"
# a class that only includes gets the module method
class G
  include Mn
end
p(G.new.nn)   # "module"
