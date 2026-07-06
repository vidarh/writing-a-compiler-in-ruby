# Float comparison codegen (flt/fgt/feq via x87 fucompp). Guards value-correctness AND the
# earlier crash where <=> assigned a RAW 0 (a null pointer) for the equal case. NaN comparisons
# must be all-false and <=> nil (unordered). Verified against MRI.
p(1.5 <=> 2.5)   # -1
p(2.5 <=> 1.5)   # 1
p(1.5 <=> 1.5)   # 0   <- raw-0 null-pointer crash regression guard
p(1.5 < 2.5)     # true
p(2.5 <= 2.5)    # true
p(3.0 >= 2.0)    # true
p(2.0 == 2)      # true (Integer coercion)
p(1.0.eql?(1))   # false (strict type)
n = 0.0 / 0.0
p(n == n)        # false (NaN)
p(n <=> 1.0)     # nil  (unordered)
