#
# Stubbed out missing pieces
#
#

# FIXME:
# Should auto-generate this so it actually has the correct value...
# However it requires String support to be functional first.
#
__FILE__ = "lib/core/stubs.rb"


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

def raise *exp
  puts "ERROR: Exception support not yet implemented"
  puts "ERROR: Arguments to raise were:"
  puts exp.inspect
  puts "ERROR ============="
  %s(div 0 0) # Force an exception so we can trap it easily in gdb.
end

# FIXME:
%s(defun range (a b)
  (puts "Compiler range construct is not implemented yet")
)

# FIXME
LOAD_PATH=[]

# FIXME: We'll pick something else for this; for now I just
# need *something* to distinguish from MRI.
RUBY_ENGINE="vidarh/compiler"

