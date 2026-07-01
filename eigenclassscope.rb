# EigenclassScope - ClassScope for eigenclass method definitions
#
# Sits between LocalVarScope and FuncScope to provide a ClassScope
# for method registration while allowing variable resolution to
# fall through to @next.

class EigenclassScope < ClassScope
  # Override lvaroffset to delegate to @next
  # This is needed so LocalVarScope offset calculations work correctly
  # when EigenclassScope is in the middle of the scope chain
  def lvaroffset
    @next ? @next.lvaroffset : 0
  end

    # Defer to parents class variable.
  # FIXME: This might need to actually dynamically
  # look up the superclass?
  def get_class_var(var)
    @next.get_class_var(var)
  end

  def get_arg(var, save = false)
    if var == :self
      return @next.get_arg(var, save)
    end
    super(var, save)
  end

  # Instance variables inside an eigenclass method (`def self.foo`, `class << self`) belong to the
  # CLASS OBJECT, not to instances. The class object's slots hold its vtable/metadata, so a slot-based
  # ivar offset (the ClassScope default) lands on a method pointer: writing corrupts a method, and
  # reading an *uninitialized* one yields a code address -- non-nil, so `@x ||= v` keeps it and then
  # dereferences it as an object => SIGSEGV. Store class-object ivars in a global keyed by the enclosing
  # class instead (as ClassScope does for @@class vars), so all of a class's singleton methods share one
  # location. `prefix` is the enclosing class path with a trailing "__" (derived from the @next chain and
  # identical for every def-self of that class); strip the "__" to get the class name.
  def get_instance_var(a)
    # NB: use a Range slice, not the 2-arg String#[](start,len) form -- the self-hosted String#[] only
    # accepts a single Integer/Range argument, so `prefix[0, n]` breaks selftest-c.
    p = prefix
    cname = p.length >= 3 ? p[0..(p.length - 3)] : "__main"
    g = "__classivar__#{cname}__#{a.to_s[1..-1]}"
    add_global(g)
    return [:global, g.to_sym]
  end
end
