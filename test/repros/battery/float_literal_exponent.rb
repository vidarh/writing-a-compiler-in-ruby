# A float literal may carry an exponent with NO decimal point (10e15, 1e-9, 2E5) -- Ruby treats these
# as Floats. The lexer previously only parsed an exponent after a decimal point, so `10e15` tokenized
# as `10` followed by a method call `e15` (undefined-method error). The exponent is e/E + optional sign
# + at least one digit; anything else (an identifier/keyword/constant starting with e or E) is left to
# tokenize normally. Verified against MRI.
p(10e15)                 # 1.0e+16
p(1e-9)                  # 1.0e-09
p(2E5)                   # 200000.0
p(1e3.class)             # Float
p((-1e-15) < 0.0)        # true
p(1.5e3)                 # 1500.0   (decimal-with-exponent still works)
p(1e2 == 100.0)          # true
p(5e0 == 5.0)            # true
# e/E NOT starting a valid exponent must be unaffected
def each_x; 7; end
p(each_x)                # 7
E_CONST = 9
p(E_CONST)              # 9
p(0xff)                  # 255  (hex unaffected)
p(5r)                    # (5/1)  (rational unaffected)
x = 3
p(x)                     # 3
p((1e2..1e3).class.to_s) # "Range"
