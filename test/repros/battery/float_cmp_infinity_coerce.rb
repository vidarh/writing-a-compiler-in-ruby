# Float#<=> / Integer#<=> extended paths. Float#<=> now: (a) returns an infinity's sign directly
# for an Integer operand instead of converting it (a bignum would overflow to +/-Infinity and
# collapse a strict comparison to 0); (b) consults other.infinite? when self is infinite and other
# is a non-numeric that responds to it; (c) follows the coerce protocol otherwise, raising TypeError
# on a non-[x,y] return and returning nil for an operand with no #coerce. Integer#<=> mirrors (a):
# an infinite Float operand fixes the order without routing self through Float. Verified against MRI.
huge = (2 ** 200)                    # bignum, finite
inf  = 1.0 / 0.0
p(inf <=> huge)                      # 1   (+Inf beats any finite integer, no overflow)
p((0.0 - inf) <=> huge)              # -1
p(huge <=> inf)                      # -1  (Integer#<=> infinite Float)
p(huge <=> (0.0 - inf))             # 1
p((-huge) <=> (0.0 - inf))          # 1   (bignum.to_f would be -Inf -> spurious 0 without the fix)

# other.infinite? protocol (plain object, self is infinite)
class MyInf
  def initialize(v); @v = v; end
  def infinite?; @v; end
end
p(inf <=> MyInf.new(1))              # 0   (both +infinite)
p(inf <=> MyInf.new(-1))            # 1
p(inf <=> MyInf.new(nil))           # 1   (other is finite)

# coerce protocol
class Coerce42
  def coerce(other); [other, 42.0]; end
end
p(2.33 <=> Coerce42.new)             # -1
p(42.0 <=> Coerce42.new)             # 0
p(43.0 <=> Coerce42.new)             # 1

# non-coercible operand -> nil (no exception)
p(1.0 <=> "1")                       # nil
p(1.0 <=> :one)                      # nil

# misbehaving coerce -> TypeError (must not crash)
class BadCoerce
  def coerce(other); :nope; end
end
begin
  1.0 <=> BadCoerce.new
  p "no error"
rescue TypeError => e
  p e.message                        # "coerce must return [x, y]"
end
