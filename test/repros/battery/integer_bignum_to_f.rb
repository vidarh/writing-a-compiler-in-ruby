# Integer#to_f used the x87 fildl primitive unconditionally, which loaded a heap bignum's object
# pointer as garbage (e.g. (2**64).to_f == 725532144.0). Now a tagged fixnum (bit 0 == 1) still uses
# fildl, and a heap bignum converts through its exact decimal string (to_s.to_f / strtod). Fixnum
# behavior must be unchanged.
p(100.to_f)          # 100.0
p((-100).to_f)       # -100.0
p(0.to_f)            # 0.0
p(536870911.to_f)    # 536870911.0
p((2 ** 64).to_f)    # 1.8446744073709552e+19
p((10 ** 20).to_f)   # 1.0e+20
p((-(2 ** 64)).to_f) # -1.8446744073709552e+19
p(1.0 + (2 ** 64))   # 1.8446744073709552e+19  (Float coerce + bignum to_f)
