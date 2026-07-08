# MRI's Math functions are also available as (private) instance methods when a class does
# `include Math`; the specs invoke them via send. module_function is a no-op stub here, so Math
# provides explicit instance-method delegates to its module methods. Verified against MRI.
class IncMath
  include Math
  def t_sin(x); send(:sin, x); end
  def t_sqrt(x); send(:sqrt, x); end
  def t_log(x); send(:log, x); end
  def t_atan2(a, b); send(:atan2, a, b); end
  def t_gamma(x); send(:gamma, x); end
  def t_ldexp(f, n); send(:ldexp, f, n); end
  def t_frexp(x); send(:frexp, x); end
end
def close(a,b); (a-b).abs < 0.00001; end
m = IncMath.new
p(close(m.t_sin(1.21), 0.935616001553386))   # true
p(close(m.t_sqrt(4), 2.0))                    # true
p(close(m.t_log(Math::E), 1.0))               # true
p(close(m.t_atan2(1, 1), 0.7853981633974483)) # true
p(m.t_gamma(5) == 24)                          # true
p(m.t_ldexp(1.0, 3) == 8.0)                    # true
p(m.t_frexp(8.0) == [0.5, 4])                  # true
# module methods still work
p(close(Math.sin(1.21), 0.935616001553386))   # true
