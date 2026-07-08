# Complex#eql? is stricter than #==: it never coerces, requires the other object to be a Complex whose
# corresponding parts are the SAME class, and requires == equality (it does not send #eql? to the parts).
# Complex#== compares parts against another Complex; against a real numeric it is equal iff the imaginary
# part is zero and the real parts are ==; against anything else it reflects (other == self). Verified vs MRI.

# eql?
p(Complex(1).eql?(1))               # false -- not a Complex
p(Complex(1, 2).eql?(Complex(1, 2)))    # true  -- same classes, ==
p(Complex(1).eql?(Complex(1.0)))    # false -- real parts differ in class (Integer vs Float)
p(Complex(1, 2).eql?(Complex(1, 2.0))) # false -- imaginary parts differ in class
p(Complex(1, 2).eql?(Complex(2, 3))) # false -- not ==

# == against a real numeric: equal only when the imaginary part is zero
p(Complex(3, 0) == 3)               # true
p(Complex(3, 0) == 4)               # false
p(Complex(3, 1) == 3)               # false -- non-zero imaginary part
p(Complex(3.0, 0) == 3)             # true
p(Complex(3, 0) == 3.0)             # true

# == against another Complex
p(Complex(1, 2) == Complex(1, 2))   # true
p(Complex(1, 2) == Complex(1, 3))   # false

# == reflects to `other == self` for a non-numeric object; here the object always answers true
class AlwaysEq
  def ==(o); true; end
end
p(Complex(5, 6) == AlwaysEq.new)    # true -- reflected to AlwaysEq#==
