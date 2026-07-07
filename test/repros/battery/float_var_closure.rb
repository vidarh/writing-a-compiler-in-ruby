# Regression guard: a captured local named `float` collides with the [:float, "<dec>"] literal
# node tag. In the closure env-var rewrite (__rewrite_node_refs), the position-0 :float of the
# literal was rewritten into an [:index,__env__,k] read, so `float = 2.4` inside a block emitted
# the decimal as a raw String whose ADDRESS was later dispatched on -> SIGSEGV. Fixed by guarding
# the node tag (only when e[1] is the String payload, so a bare `float` arg is still rewritten).
pr = proc { float = 2.4; p float.dup.class }        # Float
pr.call
[1].each { |i| flt = 1.5; p((flt + 0.5).to_i) }     # 2
o = proc { inner = proc { float = 3.5; p float.to_i }; inner.call }  # 3
o.call
# `float` as a bare argument (1-element arg list) must still resolve as the variable:
check = proc { |a, b| a.equal?(b) }
p2 = proc { float = 9.0; p check.call(float, float) }  # true
p2.call
