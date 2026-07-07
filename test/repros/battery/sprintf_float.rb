# sprintf %f/%e/%g/%E/%G for Floats via C snprintf (__snprintf_float). Previously all routed through
# the pure-Ruby fixed-decimal __format_float, so %e/%g were wrong. Verified vs MRI.
puts sprintf("%f", 3.14159)       # 3.141590
puts sprintf("%.2f", 3.14159)     # 3.14
puts sprintf("%e", 31415.9)       # 3.141590e+04
puts sprintf("%g", 0.0001)        # 0.0001
puts sprintf("%g", 1000000.0)     # 1e+06
puts sprintf("%E", 12345.678)     # 1.234568E+04
puts sprintf("%8.2f", 3.14159)    #     3.14
puts sprintf("%-8.2f|", 3.14159)  # 3.14    |
puts sprintf("%+.2f", 3.14159)    # +3.14
puts sprintf("%f", -2.5)          # -2.500000
