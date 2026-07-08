# A float literal that overflows the IEEE double range is +/-Infinity (MRI), and gas cannot assemble a
# .double for it ("cannot create floating-point number"), so the compiler emits the Infinity bit
# pattern via .quad for a clearly-overflowing literal. Verified against MRI.
p(1e1020)        # Infinity
p(-1e1020)       # -Infinity
p(1e400)         # Infinity
p(1.0e308)       # 1.0e+308 (valid, not overflow)
p(1.5e10)        # 15000000000.0 (normal)
p(1e1020.infinite?)   # 1
p((-1e1020).infinite?) # -1
p(2.5)           # 2.5 (normal float still works)
p(1e1020 == Float::INFINITY)  # true
