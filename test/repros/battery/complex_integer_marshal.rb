# Complex#integer? is always false (a Complex is never an Integer, even with a zero imaginary part).
# Complex#marshal_dump returns [real, imag]. (MRI marks marshal_dump private and defines no marshal_load;
# `private` is a no-op in this runtime so the method stays public, but #send reaches it as the spec does.)
# Verified vs MRI.
p(Complex(20).integer?)              # false
p(Complex(1, 2).integer?)            # false
p(Complex(0, 0).integer?)            # false
p(Complex(1, 2).send(:marshal_dump))       # [1, 2]
p(Complex(-3, 4).send(:marshal_dump))      # [-3, 4]
p(Complex(1.5, 0).send(:marshal_dump))     # [1.5, 0]
