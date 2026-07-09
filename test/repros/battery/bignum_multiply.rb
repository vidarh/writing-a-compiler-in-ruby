# heap*heap multiply lost carries when a low word had bit 31 set (signed overflow check). 10**n for
# large n and dense products were wrong past ~8 limbs. Fixed via unsigned overflow compare.
raise "m1" unless 10**40 * 10**40 == 10**80
raise "m2" unless (10**100) * (10**100) == 10**200
raise "m3" unless (2**100) * (2**100) == 2**200
raise "d1" unless (10**80 + 123456789) / 7 == (10**80 + 123456789) / 7
puts "ok"
