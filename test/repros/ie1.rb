# instance_exec must forward its arguments to the block unshifted
# (blkarg slot must not eat the first argument).
r = 42.instance_exec(1, 2) { |a, b| [a, b, self] }
puts r.inspect
s = "x".instance_eval { self.length }
puts s.inspect
# expected:
# [1, 2, 42]
# 1
