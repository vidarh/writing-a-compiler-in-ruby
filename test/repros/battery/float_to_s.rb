# Float#to_s / #inspect v1 via the C helper __float_to_cstr (tgc.c): shortest round-trip through
# strtod, then MRI's fixed/scientific placement (fixed for decimal exponent in [-4,14]). Guards the
# codegen + C-call path against crashes; value-correctness is verified against MRI separately. Before
# this, to_s was a "0.0" stub and float/to_s + float/inspect CRASHED.
puts 2.4.to_s          # 2.4
puts 100.0.to_s        # 100.0
puts 1000000.0.to_s    # 1000000.0
puts 0.001.to_s        # 0.001
puts (-3.14).to_s      # -3.14
puts 1.0e16.to_s       # 1.0e+16
puts 2.5e-10.to_s      # 2.5e-10
puts (1.0/0.0).to_s    # Infinity
puts (-1.0/0.0).to_s   # -Infinity
puts (0.0/0.0).to_s    # NaN
puts 42.0.inspect      # 42.0
puts((1.0/3.0).to_s)   # 0.3333333333333333
