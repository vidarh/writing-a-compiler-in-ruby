#
# Stubbed out missing pieces
#
#

# FIXME:
# Should auto-generate this so it actually has the correct value...
# However it requires String support to be functional first.
#
__FILE__ = "lib/core/stubs.rb"
__LINE__ = nil


# Set up the 'main' object
#
# FIXME: This is insufficient. E.g. the object is supposed
# to return 'main' as the textual representation.
#
self = Object.new



# FIXME: This is of course just plain blatantly wrong, but
# the next goal is to get everything to link (and crash...)
# These fall in two categories:
#  - The ones that fails because scoped lookups doesn't
#    yet work
E = 2

#  - The ones that fails because they haven't been implemented
# Enumerable=8 #Here because modules doesn't work yet

# raise is now implemented in lib/core/kernel.rb

# FIXME:
%s(defun range (a b)
  (puts "Compiler range construct is not implemented yet")
)

# FIXME
$LOAD_PATH=[]

# FIXME: We'll pick something else for this; for now I just
# need *something* to distinguish from MRI.
RUBY_ENGINE="vidarh/compiler"

# Stub for Thread class (not implemented)
class Thread
end

# Stub for Module class
# FIXME: Module should be a superclass of Class, but that requires
# significant refactoring of the object model
class Module
end

# Stub for Fiber class (not implemented)
class Fiber
end
