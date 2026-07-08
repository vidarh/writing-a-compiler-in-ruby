# Complex#inspect renders each part with #inspect (Complex#to_s uses #to_s), and inserts a "*" before
# the trailing "i" whenever the imaginary magnitude does not end in a digit. This is observable where a
# part's #inspect differs from its #to_s -- e.g. a Rational part: Rational(1,2).inspect is "(1/2)" but
# its #to_s is "1/2", and "(1/2)" ends in ")" so the imaginary form gains a "*". Verified vs MRI.
#
# NOTE: core/complex/inspect_spec's "calls #inspect on real and imaginary" cases use should_receive on a
# real Numeric subclass, which the harness cannot stub (Object#should_receive is a no-op on real objects;
# a real fix needs define_singleton_method, unsupported by the compiler), so those stay unflipped -- this
# guard exercises the same code path with real Rational parts instead.
p(Complex(Rational(1, 2), 3).inspect)   # "((1/2)+3i)"
p(Complex(Rational(1, 2), 3).to_s)      # "1/2+3i"
p(Complex(1, Rational(3, 4)).inspect)   # "(1+(3/4)*i)"
p(Complex(1, Rational(3, 4)).to_s)      # "1+3/4i"
p(Complex(1, 2).inspect)                # "(1+2i)"
p(Complex(-7, 6.7).inspect)             # "(-7+6.7i)"
p(Complex(0, -1).inspect)               # "(0-1i)"
