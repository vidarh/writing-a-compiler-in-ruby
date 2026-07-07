# Float#to_i (and truncate/to_int) beyond the fixnum range must produce a bignum: it truncates toward
# zero with libm trunc (avoiding the floor/% recursion of an in-Ruby truncation) then parses the exact
# decimal string. NaN / +-Infinity raise FloatDomainError. Fixnum-range values keep the fast ftoi path.
p(899.2.to_i)                     # 899
p(5213451.9201.to_i)              # 5213451
p((-3.9).to_i)                    # -3
p(1.233450999123389e+12.to_i)     # 1233450999123
p(9223372036854775808.1.to_i)     # 9223372036854775808
p((-9223372036854775808.1).to_i)  # -9223372036854775808
p(536870911.to_f.to_i)            # 536870911 (fixnum-max boundary)
["NaN", "Inf"].each do |k|
  v = k == "NaN" ? (0.0/0.0) : (1.0/0.0)
  begin
    v.to_i
    p "no error #{k}"
  rescue FloatDomainError
    p "FloatDomainError #{k}"
  end
end
