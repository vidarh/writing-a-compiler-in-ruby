
def __method_missing
  %s(puts "default method missing")
end

def array size
  malloc(size*4)
end

require 'core/kernel'
require 'core/object'
require 'core/class'
require 'core/enumerable'
#require 'core/array'
require 'core/hash'
require 'core/string'
require 'core/io'
require 'core/file'
require 'core/symbol'
require 'core/fixnum'
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
