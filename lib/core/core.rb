
def __method_missing
  %s(puts "default method missing")
end

def array size
  malloc(size*4)
end

require 'core/kernel'
require 'core/object'
require 'core/class'
#require 'core/enumerable'
#require 'core/array'
require 'core/string'
require 'core/io'
require 'core/file'
require 'core/symbol'
require 'core/fixnum'
require 'core/struct'

