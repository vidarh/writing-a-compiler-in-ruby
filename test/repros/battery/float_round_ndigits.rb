# Float#floor/ceil/round/truncate gained an optional ndigits argument. Previously they took no
# arg, so `x.floor(2)` raised "wrong number of arguments (given 1, expected 0)". ndigits > 0 keeps
# that many decimals (Float); ndigits == 0 / no-arg returns an Integer; ndigits < 0 rounds to a
# power of ten (Integer). The no-arg forms (used internally by %, divmod) must be unchanged.
p(7.0.floor(1))        # 7.0
p(-1.234.floor(2))     # -1.24
p(214.94.floor(-1))    # 210
p(2.1679.ceil(2))      # 2.17
p(1.235.round(2))      # 1.24
p(1.2345.truncate(2))  # 1.23
p(-1.2345.truncate(2)) # -1.23
# no-arg forms unchanged (Integer results)
p(2.5.floor)           # 2
p((-7.5).floor)        # -8
p(7.5.ceil)            # 8
p(2.6.round)           # 3
p(3.7.truncate)        # 3
# internal callers still work
p(7.5 % 2.0)           # 1.5
p(7.5.divmod(2.0))     # [3, 1.5]
