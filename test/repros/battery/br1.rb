p "hello"[1, 3]
p [10, 20, 30].index { |x| x > 15 }
h = Hash.new { |hh, k| hh[k] = k.to_s * 2 }
p h[:ab]
p (1..).first(3)
p ("a" + ("b").upcase)
