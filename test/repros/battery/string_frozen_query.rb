# String#frozen? on a never-frozen string crashed: direct `@frozen` ivar access on a String reads a
# BROKEN slot (separate from the real ivar table -- instance_variable_get returns nil while bare
# `@frozen` returns raw garbage), so `"x".frozen?` returned a non-object that SIGSEGV'd any use of the
# result (`.should`, `p`, `==`). This one crash took out core/file/basename, core/file/extname,
# core/kernel/object_id, core/string/clone, core/string/chilled_string. frozen? now returns false
# (frozen strings unsupported) and freeze is a no-op.
p("test".frozen?)                 # false
p("test".frozen?.class)           # FalseClass
p("test".frozen? == false)        # true
s = "hi"
p(s.freeze.equal?(s))             # true  (freeze returns self)
p([1, 2].frozen?)                 # false (Array frozen? already safe, must stay working)
p(nil.frozen?)                    # true
p(5.frozen?)                      # true
