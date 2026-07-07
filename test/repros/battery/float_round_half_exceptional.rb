# Float#round(*args) rewrite: half-way modes via libm (:up->round, :even->rint, :down->ceil/floor),
# a trailing options Hash parsed off the splat so `half:` works without keyword-arg binding, ndigits
# taken via #to_int (Float 3.999 -> 3; a String/nil -> TypeError), and exceptional-value handling.
# Guards value-correctness AND that none of the new raise/coerce paths crash. Verified against MRI.
p(0.49999999999999994.round)     # 0    <- libm round, not the (self+0.5).floor overflow to 1
p((-0.49999999999999994).round)  # 0
p(2.5.round(half: :up))          # 3
p(2.5.round(half: :even))        # 2    (banker's rounding)
p(3.5.round(half: :even))        # 4
p(2.5.round(half: :down))        # 2
p((-2.5).round(half: :down))     # -2
p(2.5.round(half: nil))          # 3    (nil -> default :up)
p(12.345678.round(3.999))        # 12.346  (ndigits truncated to 3 via to_int)
p(42.0.round(308))               # 42.0    (precision beyond the value -> self)
p(1.0e307.round(2))              # 1.0e+307 (scaling overflows -> self)
p(0.42.round(2.0**30))           # 0.42    (huge ndigits -> self)
p((-0.0).round(1).inspect)       # "-0.0"  (sign of zero preserved)
p((0.0).round(5).inspect)        # "0.0"
p(Float::INFINITY.round(2))      # Infinity (non-negative precision returns self)
p(123456.78.round(-2))           # 123500
p((-123456.78).round(-2))        # -123500

def try(&b)
  begin
    b.call
    p "no-raise"
  rescue => e
    p e.class.to_s
  end
end
try { 1.0.round("4") }              # "TypeError"
try { 1.0.round(nil) }              # "TypeError"
try { Float::INFINITY.round(0) }    # "FloatDomainError"
try { Float::INFINITY.round(-2) }   # "FloatDomainError"
try { (0.0/0.0).round(0) }          # "RangeError"  (NaN, explicit precision)
try { (0.0/0.0).round }             # "FloatDomainError"  (NaN, bare round)
try { 14.2.round(half: :bogus) }    # "ArgumentError"
