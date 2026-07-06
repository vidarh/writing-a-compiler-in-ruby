# Float unary ops (fneg/fabs), predicates, and real INFINITY/NAN constants. Guards value-correctness
# and the class-load path (INFINITY/NAN are computed via 1.0/0.0 & 0.0/0.0 at the bottom of the
# class body; gas cannot assemble overflowing/NaN literals). Verified against MRI.
p((3.5).abs.to_i)               # 3
p((-2.5).abs.to_i)              # 2   (negative literal)
p((4.0.-@).to_i)                # -4  (fneg via explicit -@ dispatch)
p(0.0.zero?)                    # true
p(1.5.zero?)                    # false
p((0.0 / 0.0).nan?)             # true
p(1.5.nan?)                     # false
p(Float::INFINITY.infinite?)    # 1
p((0.0 - Float::INFINITY).infinite?)  # -1
p(1.5.infinite?)                # nil
p(Float::INFINITY.finite?)      # false
p(1.5.finite?)                  # true
p(Float::NAN.nan?)              # true
p(Float::MAX > 1.0e300)         # true
p(Float::INFINITY > Float::MAX) # true
