# Double &block forwarding: re-forwarding an &block PARAM to another method's
# &block corrupts the callee's view -- block.call returns always-truthy garbage.
# Single-level forwarding works (see g1); two levels (g2 -> g1) breaks.
# Related: KNOWN_ISSUES 3b (block channel fragility).
# Expected output:
#   [false, true]
#   [false, true]
class F
  def g1(&b)
    [b.call(1), b.call(3)]
  end

  def g2(&b)
    g1(&b)
  end
end
f = F.new
p f.g1 { |x| x > 2 }
p f.g2 { |x| x > 2 }
