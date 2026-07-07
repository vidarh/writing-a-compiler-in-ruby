# Float#floor/ceil/round/truncate (no-arg, Integer result). floor toward -inf, ceil toward +inf,
# truncate/to_i toward zero, round half-away-from-zero. Verified vs MRI.
p(3.7.floor)     # 3
p(3.2.ceil)      # 4
p((-3.2).floor)  # -4
p((-3.7).ceil)   # -3
p(2.5.round)     # 3
p((-2.5).round)  # -3
p(2.4.round)     # 2
p(3.7.truncate)  # 3
p((-3.7).truncate) # -3
p(3.0.floor)     # 3  (integer-valued, no off-by-one)
p((-3.0).ceil)   # -3
