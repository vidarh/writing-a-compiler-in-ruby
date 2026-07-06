# Float arithmetic + Integer<->Float conversion value-correctness. Guards the x87 codegen
# (fadd/fsub/fmul/fdiv/ftoi/fint). Values are checked THROUGH to_i (truncation toward zero),
# since Float#to_s is still a stub. Prior to this the operators returned `self` and to_i/to_f
# were stubs returning 0 / a 0.0 object.
a = 1.5
b = 2.5
p((a + b).to_i)         # 4   (4.0)
p((b - a).to_i)         # 1   (1.0)
p((a * b).to_i)         # 3   (3.75 truncated)
p((10.0 / 4.0).to_i)    # 2   (2.5 truncated)
p(3.to_f.to_i)          # 3   (Integer#to_f then back)
p((3.to_f + 1.5).to_i)  # 4   (mixed-operand coercion: 4.5 truncated)
p((0.0 - 7.5).to_i)     # -7  (truncate toward zero, not floor)
p(4.to_f.class)         # Float
