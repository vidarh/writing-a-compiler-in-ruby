# Float#% (modulo): a zero divisor (Integer 0 or Float 0.0) raises ZeroDivisionError; an infinite
# divisor keeps the divisor's sign (self, or self+other on a sign mismatch) rather than the NaN the
# self-(self/other).floor*other formula would give (0.0*Inf==NaN); NaN operands / infinite dividend
# give NaN. Finite cases are unchanged.
p(6543.21 % 137 > 104.0)              # true (~104.21)
p(-1.0 % 1)                            # 0.0
p(4.2 % Float::INFINITY)               # 4.2
p(4.2 % (0.0 - Float::INFINITY))       # -Infinity
p((-4.2) % Float::INFINITY)            # Infinity
p(((0.0/0.0) % 2).nan?)               # true
begin; 1.0 % 0;   p "no"; rescue ZeroDivisionError; p "ZD int"; end
begin; 1.0 % 0.0; p "no"; rescue ZeroDivisionError; p "ZD float"; end
p(7.5 % 2.0)                           # 1.5 (internal divmod caller unchanged)
