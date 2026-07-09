# An unset user ivar on an Array/String subclass must read as nil, not the raw 0 __array (calloc)
# leaves -- a method call on raw 0 segfaulted. Array/String .self.allocate nil-init subclass slots.
class AA < Array; attr_accessor :m; end
raise "arr" unless AA.new([1,2]).m.nil?
class SS < String; attr_accessor :m; end
raise "str" unless SS.new("x").m.nil?
puts "ok"
