# IEEE-754 double parameter constants on Float (were undefined -> "uninitialized constant" aborted
# float/constants mid-file). Values match MRI.
p(Float::RADIX)       # 2
p(Float::MIN_EXP)     # -1021
p(Float::MAX_EXP)     # 1024
p(Float::MIN_10_EXP)  # -307
p(Float::MAX_10_EXP)  # 308
p(Float::MANT_DIG)    # 53
p(Float::DIG)         # 15
