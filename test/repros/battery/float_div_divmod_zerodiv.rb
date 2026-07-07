# Float#div / #divmod raise ZeroDivisionError on a zero divisor and FloatDomainError when self is
# NaN/Infinite (via floor -> to_i), matching MRI. Non-numeric operands follow the coercion protocol.
p(3.14.divmod(2))     # [1, 1.14...]
p(7.5.div(2.0))       # 3
p((-7.5).div(2.0))    # -4
begin; 1.0.div(0);        p "no"; rescue ZeroDivisionError; p "ZD div"; end
begin; 1.0.divmod(0.0);   p "no"; rescue ZeroDivisionError; p "ZD divmod"; end
begin; (0.0/0.0).divmod(1); p "no"; rescue FloatDomainError; p "FDE nan"; end
