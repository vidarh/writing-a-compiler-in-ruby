# Complex exact-arithmetic subset (lib/core/complex.rb): +, -, *, ==, conjugate, abs2, rectangular,
# negation, formatting, and Integer<->Complex coercion. Magnitude/argument/division are omitted (they
# need Float). Prints identically under MRI and the self-hosted compiler.
p Complex(3, 4)                    # (3+4i)
p Complex(3, -4)                   # (3-4i)
p Complex(3, 4).to_s               # "3+4i"
p(Complex(3, 4) + Complex(1, 2))   # (4+6i)
p(Complex(3, 4) - Complex(1, 2))   # (2+2i)
p(Complex(3, 4) * Complex(1, 2))   # (-5+10i)
p(Complex(3, 4) * 2)               # (6+8i)
p(Complex(3, 4) + 5)               # (8+4i)
p(2 + Complex(3, 4))               # (5+4i)  (Integer coerces)
eq = (Complex(3, 4) == Complex(3, 4)); p eq          # true
req = (Complex(3, 0) == 3); p req                     # true
p Complex(3, 4).conjugate          # (3-4i)
p Complex(3, 4).abs2               # 25
p Complex(3, 4).rectangular        # [3, 4]
p Complex(3, 4).imaginary          # 4
p(-Complex(3, 4))                  # (-3-4i)
