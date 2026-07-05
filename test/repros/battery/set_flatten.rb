# Guards Set#flatten recursion: a self-referential set (set << set) recursed through #flatten forever
# and segfaulted (core/set/flatten_spec). MRI raises ArgumentError for a recursive set; a Set that
# merely appears twice without a cycle still flattens.
require 'set'
s = Set[1, 2, Set[3, 4, Set[5, 6]], 7]
p s.flatten.to_a.sort     # [1, 2, 3, 4, 5, 6, 7]

r = Set[]
r << r
begin
  r.flatten
  p "no-error"
rescue ArgumentError
  p "ArgumentError"        # ArgumentError (not a segfault)
end
