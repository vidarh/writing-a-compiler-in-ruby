# Integer <op> Float comparisons must coerce (the `(sar other)` fast path mangled a Float pointer,
# so int<float returned false and int<=>float returned nil). Now delegates to the real Float ops.
p(1 <= 2.5)      # true
p(3 <= 2.5)      # false
p(1 < 2.5)       # true
p(3 > 2.5)       # true
p(2 >= 2.0)      # true
p(2 == 2.0)      # true
p(1 <=> 2.5)     # -1
p(3 <=> 2.5)     # 1
p(2 <=> 2.0)     # 0
p(5.between?(1.0, 10.0))  # true
p(5.downto(1).to_a)       # [5,4,3,2,1] (integer loops unaffected)
n=0; 1.step(Float::INFINITY, 42) { |x| n+=1; break if x > 200 }; p n  # 6
