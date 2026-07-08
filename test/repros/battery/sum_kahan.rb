# Array#sum / Enumerable#sum / Enumerator#sum use Kahan compensated summation once a Float is involved,
# so a float total is MRI-precise (that dozen values sum to exactly 50.0, not 50.00000000000001). Plain
# #+ accumulation is kept for non-float elements. Verified vs MRI.
floats = [2.7800000000000002, 5.0, 2.5, 4.44, 3.89, 3.89, 4.44, 7.78, 5.0, 2.7800000000000002, 5.0, 2.5]
p(floats.sum)              # 50.0  (Array#sum)
p(floats.to_enum.sum)      # 50.0  (Enumerator#sum via to_enum)
p([1, 2, 3].sum)           # 6     (integer, plain +)
p([1, 2, 3].sum(10))       # 16
p([1.0, 2.0, 3.0].sum)     # 6.0
p([1, 2.5].sum)            # 3.5   (mixed int/float)
p([].sum)                  # 0
p([].sum(5))               # 5
