# Float ordered comparisons (< > <= >=) coerce a non-numeric operand and raise ArgumentError
# ("comparison of Float with X failed") when it cannot be coerced, matching MRI -- instead of the old
# NoMethodError from other.to_f. Numeric operands and NaN semantics are unchanged.
p(1.0 < 2)     # true
p(2.0 < 1)     # false
p(1.5 <= 1.5)  # true
p(3.0 > 2)     # true
p(2.0 >= 3)    # false
["<", ">", "<=", ">="].each do |op|
  begin
    1.0.send(op.to_sym, "x")
    p "no error #{op}"
  rescue ArgumentError
    p "ArgumentError #{op}"
  rescue
    p "wrong #{op}"
  end
end
