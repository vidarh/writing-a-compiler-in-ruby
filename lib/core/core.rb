
%s(defun __method_missing (sym ob (args rest)) (let (k cname)
  (assign k     (callm ob class))
  (assign cname (callm ob inspect))
  (printf "Method missing: %s#%s\n" (callm (callm cname to_s) __get_raw) (callm (callm sym to_s) __get_raw))
  (div 0 0)
  0)
)

%s(defun __array (size) (malloc (mul size 4)))

# FIXME: Need to bootstrap Object in first, so that Class inherits
#  the appropriate methods.
# Must be the first file to be require'd, in order to initialize the Class constant.
require 'core/class'

# FIXME: Should probably add "autoload" of all but the
# most basic of these
require 'core/kernel'
require 'core/object'
require 'core/proc'   # Proc is required before blocks can be used

# Due to splat handling, this *must* occur before the
# first splat method call
require 'core/array_base'

require 'core/true'
true = TrueClass.new # FIXME: MRI does not allow creating an object of TrueClass
require 'core/false'
false = FalseClass.new # FIXME: MRI does not allow creating an object of FalseClass
require 'core/nil'
nil  = NilClass.new # FIXME: MRI does not allow creating an object of NilClass.

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

require 'core/numeric'
require 'core/integer'
require 'core/fixnum'
require 'core/symbol'
require 'core/class_ext'
require 'core/hash_ext'
require 'core/float'
require 'core/struct'
require 'core/exception'
require 'core/pp'
require 'core/range'

# FIXME: This is of course just plain blatantly wrong, but
# the next goal is to get everything to link (and crash...)
# These fall in two categories:
#  - The ones that fails because scoped lookups doesn't
#    yet work
E = 2
Tokens=5
#  - The ones that fails because they haven't been implemented
STDIN= IO.new
STDERR=IO.new
STDOUT = IO.new
Enumerable=8 #Here because modules doesn't work yet

# FIXME:
%s(defun range (a b)
  (puts "Compiler range construct is not implemented yet")
)


%s(defun printregs (regs) (do
  (printf "eax: %08x, ebx: %08x, ecx: %08x, edx: %08x, esi: %08x, edi: %08x, ebp: %08x, esp: %08x\n"
   (index regs 0)
   (index regs 1)
   (index regs 2)
   (index regs 3)
   (index regs 4)
   (index regs 5)
   (index regs 6)
   (index regs 7))

  (assign sp (index regs 6))
  (printf "(ebp): %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x\n"
   (index sp 0)
   (index sp 1)
   (index sp 2)
   (index sp 3)
   (index sp 4)
   (index sp 5)
   (index sp 6)
   (index sp 7)
   (index sp 8)
   (index sp 9)
)

  (assign sp (index regs 7))
  (printf "(esp): %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x\n"
   (index sp 0)
   (index sp 1)
   (index sp 2)
   (index sp 3)
   (index sp 4)
   (index sp 5)
   (index sp 6)
   (index sp 7))

))
