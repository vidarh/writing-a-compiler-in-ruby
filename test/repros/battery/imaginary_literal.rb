# A trailing `i` on a numeric literal is the imaginary suffix: 5i -> Complex(0, 5), 3.2i -> Complex(0,
# 3.2), 0.0i -> Complex(0, 0.0). It only applies when the `i` does not run into an identifier, so
# `5if` stays `5 if` and `5in` stays `5 in`. Works for integer, decimal, and exponent number forms.
# Verified against MRI.
p(5i == Complex(0, 5))          # true
p(2i.class)                     # Complex
p(3.2i == Complex(0, 3.2))      # true
p(0.0i == Complex(0, 0.0))      # true
p(0i == Complex(0, 0))          # true
p(1i * 1i == Complex(-1, 0))    # true  (i**2 == -1)
p((3 + 4i) == Complex(3, 4))    # true
p((1.5 + 2.5i) == Complex(1.5, 2.5))  # true
p(1e2i == Complex(0, 100.0))    # true  (exponent form)
# identifier collision: `i` running into a keyword/identifier is NOT the suffix
x = 5
p(x if x > 0)                   # 5   (parsed as `x if ...`)
p(5 if true)                    # 5   (`5 if true`, not 5i followed by f)
n = 7
p(n)                            # 7
