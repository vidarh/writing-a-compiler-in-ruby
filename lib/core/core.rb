
%s(defun __method_missing (sym) (do
  (printf "Method missing: %s\n" (callm (callm sym to_s) __get_raw))
  (exit 1)
  0)
)

%s(defun array (size) (malloc ((mul size 4))))

# FIXME: Need to bootstrap Object in first, so that Class inherits
#  the appropriate methods.
# Must be the first file to be require'd, in order to initialize the Class constant.
require 'core/class'

# FIXME: Should probably add "autoload" of all but the
# most basic of these
require 'core/kernel'
require 'core/object'
require 'core/proc'   # Proc is required before blocks can be used

# OK, so perhaps this is a bit ugly...
self = Object.new

require 'core/enumerable'
require 'core/array'
require 'core/string'  # "string" must be early on for __get_string calls not to fail

# Should auto-generate this so it actually has the correct value...
__FILE__ = "[filename]"


require 'core/hash'
require 'core/io'
require 'core/file'
require 'core/symbol'

require 'core/numeric'
require 'core/integer'
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
%s(defun range (a b)
  (puts "Compiler range construct is not implemented yet")
)
