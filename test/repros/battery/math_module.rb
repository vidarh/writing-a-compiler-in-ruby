# Math module: DIRECT libc math.h calls (sqrt/exp/log/... via %s, double args as two halves, st0->fstresult).
p(Math.sqrt(2.0).to_s)         # 1.4142135623730951
p(Math.sqrt(16).to_s)          # 4.0
p(Math.exp(0.0).to_s)          # 1.0
p(Math.log(Math::E).to_s)      # 1.0
p(Math.log(8.0, 2.0).to_s)     # 3.0
p(Math.hypot(3.0, 4.0).to_s)   # 5.0
p(Math.atan2(1.0, 1.0).to_s)   # 0.7853981633974483
begin; Math.sqrt(-1.0); puts "NO"; rescue Math::DomainError; puts "DomainError"; end
