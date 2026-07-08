# Float#quo mirrors Float#fdiv's argument handling: a real numeric divisor converts to Float and
# divides; a Complex (or anything else responding to #coerce) goes through the coercion protocol so
# `float.quo(Complex)` divides via Complex#quo instead of raising on Complex#to_f; a non-numeric,
# non-coercible value (String has #to_f but is not Numeric; Array) is a TypeError. Verified vs MRI.
def try
  begin
    yield.inspect
  rescue => e
    e.class.to_s
  end
end
p(74620.09.quo(Complex(8, 2)).inspect)   # "(8778.834117647059-2194.7085294117646i)"
p(6.0.quo(2))                            # 3.0
p(6.0.quo(2.5))                          # 2.4
p(6.0.quo(Rational(3, 2)))               # 4.0
p(try { 6.0.quo("s") })                  # "TypeError"
p(try { 6.0.quo([]) })                   # "TypeError"
