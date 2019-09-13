#
# This file is automatically loaded unless automatic requires
# are switched off. It is responsible for bootstrapping as
# much as possible of the Ruby type system, all the way down
# to Object and Class.
#
# The ordering of require statements is critical in this
# file. At some point internal dependencies in the file
# might get added to reduce the potential for breakage,
# but or now, consider that e.g. each class require'd below
# is *totally* unavailable before that point, which means
# that before "require 'core/string'" you can't instantiate
# String objects. At all.
#
# Certain classes are depended on for key language
# constructs, and so the constructs themselves will
# fail if called before the appropriate require's:
#
#  * Basics of Array (in core/array_base.rb) are needed
#    for splat handling
#
#  * TrueClass, FalseClass, NilClass are needed for the
#    true, false, nil keywords/variables to work at all
#
#  * "self" in the main body is unavailable
#
#  * Literal Hash, Array, Symbol, Fixnums are all
#    unavailable before at least the basic versions
#    of their respective classes are loaded.
#
# Certain classes, such as for example Array, are needed
# very early but unnecessarily hard to implement fully
# without other support. These classes are split into
# several files, layering in more methods as other supporting
# classes are available.
#
# Examples include:
#
#  * Array: core/array_base.rb, core/array.rb
#  * Hash:  core/hash.rb, core/hash_ext.rb
#  * Class: core/class.rb, core/class_ext.rb
#
# (FIXME: make naming and conventions for what is included
#  in each consistent)
#
#


#
# Low level s-exp machinery
#

require 'core/base'


#
# Core classes
#

require 'core/class'
require 'core/kernel'
require 'core/object'
require 'core/proc'        # Blocks are unavailable before this
require 'core/array_base'  # Splats are unavailable before this.
require 'core/true'
require 'core/false'
require 'core/nil'         # Before this, all variables must be explicitly defined.

require 'core/class_ivarinit'

#require 'core/enumerable'
require 'core/range'
require 'core/array' 
require 'core/string'
require 'core/hash'
require 'core/io'
require 'core/file'
require 'core/dir'
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
require 'core/regexp'
require 'core/enumerator'

#
# Other support
#

require 'core/args'
require 'core/stdio'
require 'core/stubs'       # Stubbed out/non-functional missing pieces
require 'core/debug'       # Low level debug support
