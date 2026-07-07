# Float arithmetic raises TypeError (not NoMethodError) when the operand cannot be coerced -- i.e. it
# does not respond to #coerce. This is MRI's behavior ("X can't be coerced into Float"). Numeric
# operands and types with a real #coerce are unaffected.
["*", "+", "-", "/"].each do |op|
  begin
    1.0.send(op.to_sym, "x")
    p "no error #{op}"
  rescue TypeError
    p "TypeError #{op}"
  rescue
    p "wrong error #{op}"
  end
end
p(2.0 * 4)   # 8.0
p(1.0 + 2)   # 3.0
p(10.0 / 4)  # 2.5
class CoOk
  def coerce(o); [o, 3.0]; end
end
p(6.0 + CoOk.new)  # 9.0
