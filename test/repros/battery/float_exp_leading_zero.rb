# Scientific-notation float literal with a LEADING-ZERO exponent (e-08, e+08, e08). The exponent was
# parsed via Int.expect, which treats a leading zero as OCTAL: "08" read "0" (octal), stopped at the
# invalid octal digit "8", and left "8" in the token stream -> the literal became "1.0e-0" followed by
# a stray integer 8, which then mis-parsed as a call `(1.0e-0)(8)` and SIGSEGV'd through the float's
# tagged bits. Exponents are always DECIMAL (e-08 == e-8); read the digits directly. This one bug
# crashed the whole float cluster (float/to_s, float/divide, float/inspect, math/asinh, numeric/quo).
p(1.0e-08)     # 1.0e-08
p(1.0e-09)     # 1.0e-09
p(2.0e-08)     # 2.0e-08
p(1.0e+08)     # 100000000.0
p(1.0e08)      # 100000000.0
p(-2.12108716418061e-08)   # -2.12108716418061e-08
p(1.0e-8)      # 1.0e-08  (single-digit exponent still works)
p(1.0e-010)    # 1.0e-10  (decimal 010, NOT octal 8)
p(1.0e-07)     # 1.0e-07  (valid-octal exponents were unaffected but must stay decimal)
p(6.5e-05)     # 6.5e-05
