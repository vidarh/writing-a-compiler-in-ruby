
require 'core/class'

def __method_missing
  %s(puts "default method missing")
end
