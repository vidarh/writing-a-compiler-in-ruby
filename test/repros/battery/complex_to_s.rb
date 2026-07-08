# Complex#to_s / #inspect format the imaginary part with its own sign (so -0.0 -> "-0.0i", not
# "+-0.0i") and use a "*i" separator for a non-finite imaginary part (Infinity/NaN), since e.g.
# "Infinityi" would be ambiguous. Verified against MRI.
inf = 1.0 / 0.0
nan = 0.0 / 0.0
p(Complex(1, 5).to_s == "1+5i")             # true
p(Complex(1, -5).to_s == "1-5i")            # true
p(Complex(-2.5, -1.5).to_s == "-2.5-1.5i")  # true
p(Complex(0, 5).to_s == "0+5i")             # true
p(Complex(1, 0).to_s == "1+0i")             # true
p(Complex(1, 0.0).to_s == "1+0.0i")         # true
p(Complex(1, -0.0).to_s == "1-0.0i")        # true (negative zero)
p(Complex(1, inf).to_s == "1+Infinity*i")   # true
p(Complex(1, 0.0 - inf).to_s == "1-Infinity*i")  # true
p(Complex(1, nan).to_s == "1+NaN*i")        # true
p(Complex(1, 5).inspect == "(1+5i)")        # true
p(Complex(-2.5, 1.5).inspect == "(-2.5+1.5i)")   # true
