
def __method_missing sym
  %s(printf "Method missing: %s\n" (callm sym to_s))
  %s(exit 1)
  0
end

def array size
  malloc(size*4)
end

# FIXME: Need to bootstrap Object in first, so that Class inherits
#  the appropriate methods.
# Must be the first file to be require'd, in order to initialize the Class constant.
require 'core/class'

# Should auto-generate this so it actually has the correct value...
__FILE__ = "[filename]"

# FIXME: Should probably add "autoload" of all but the
# most basic of these
require 'core/kernel'
require 'core/object'
require 'core/enumerable'
require 'core/array'

require 'core/hash'
require 'core/string'
require 'core/io'
require 'core/file'
require 'core/symbol'
require 'core/fixnum'
require 'core/float'
require 'core/struct'
require 'core/exception'
require 'core/pp'

# FIXME: This is of course just plain blatantly wrong, but
# the next goal is to get everything to link (and crash...)
# These fall in two categories:
#  - The ones that fails because scoped lookups doesn't
#    yet work
E = 2
PTR_SIZE=4
Tokens=5
OpPrec = 6
AST = 7
Node = 8
#  - The ones that fails because they haven't been implemented
STDIN=0
STDERR = 1
ARGV=7
Enumerable=8 #Here because modules doesn't work yet
nil = 0      # FIXME: Should be an object of NilClass
true = 1     # FIXME: Should be an object of TrueClass
false = 0    # FIXME: Should be an object of FalseClass

# FIXME:
def range a,b
  puts "Compiler range construct is not implemented yet"
end
