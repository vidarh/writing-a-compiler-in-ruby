p (raise("x") rescue :caught)
v = [1,2] rescue :nope
p v
def m8; raise "y" rescue :inner; end
p m8
