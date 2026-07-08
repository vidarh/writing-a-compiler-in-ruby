# Eigenclass (singleton class) objects are sized to the full runtime __vtable_size, so routines that
# iterate a class object's vtable to __vtable_size (__include_module, instance_methods, ...) do not run
# off the end. This exercises singleton-method definition + dispatch functionally (the size/OOB fix is
# ASLR-dependent, validated by valgrind + the sweep crash count rather than a deterministic crash here).
# Verified vs MRI.
class A
  def self.cm; "class method"; end   # def self.x -> eigenclass method
  def im; "instance method"; end
end
p(A.cm)          # "class method"
p(A.new.im)      # "instance method"

# class << self form
class B
  class << self
    def cm2; "cm2"; end
  end
end
p(B.cm2)         # "cm2"

# singleton method on a specific object
o = Object.new
def o.only; "only on o"; end
p(o.only)        # "only on o"

# module method + include still work alongside eigenclasses
module M
  def self.mod_m; "mod_m"; end
  def inst_m; "inst_m"; end
end
class C
  include M
end
p(M.mod_m)       # "mod_m"
p(C.new.inst_m)  # "inst_m"
