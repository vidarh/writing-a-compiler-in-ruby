# Numeric underscore separators are allowed in a float's fractional and exponent parts (Ruby), e.g.
# 3.14159_26535_89793. The lexer previously only skipped underscores in the integer part (Int.expect),
# so the fractional digits after the first underscore tokenized as a method call. read_digits now drops
# a '_' that sits between two digits (and leaves a non-separator '_' in the stream). Verified vs MRI.
def close(a,b); (a-b).abs < 0.0000001; end
p(close(3.14159_26535_89793_23846, 3.141592653589793))  # true (Math::PI literal)
p(1_000.5 == 1000.5)          # true
p(1.5_5 == 1.55)              # true
p(2e1_0 == 20000000000.0)     # true (underscore in exponent)
p(1_000_000.25 == 1000000.25) # true
p(1.234_567.class)            # Float
# integer underscores and other literals unaffected
p(1_000_000)                  # 1000000
p(0xff_ff)                    # 65535
p(1e-9 < 1.0)                 # true (plain exponent still works)
p(1.5e3 == 1500.0)            # true
