# Rational/Complex marshal via the 'U' (marshal_dump) protocol, byte-identical to MRI.
r = Marshal.load(Marshal.dump(Rational(3, 4)))
puts(r.numerator == 3 && r.denominator == 4 ? "ok rational" : "FAIL rational")
c = Marshal.load(Marshal.dump(Complex(1, 2)))
puts(c.real == 1 && c.imag == 2 ? "ok complex" : "FAIL complex")
# wire format uses 'U' (85) + array of two ints
puts(Marshal.dump(Rational(3, 4)).bytes[2] == 85 ? "ok wire-U" : "FAIL wire-U")
