# Float#coerce/divmod/div/quo/fdiv/positive?/negative? and Integer#fdiv (was a 2.1e-314 stub).
p(5.5.coerce(2))          # [2.0, 5.5]
p(7.5.divmod(2))          # [3, 1.5]
p((-7.5).divmod(2))       # [-4, 0.5]
p(7.5.div(2))             # 3
p(7.5.quo(2))             # 3.75
p(9.0.fdiv(2))            # 4.5
p(5.5.positive?)          # true
p((-5.5).negative?)       # true
p(0.0.positive?)          # false
p(7.fdiv(2))              # 3.5  (Integer#fdiv)
p(10.fdiv(4))             # 2.5
