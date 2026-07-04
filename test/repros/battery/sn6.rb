obj = nil
p (obj&.m += 3)
p (obj&.m ||= 5)
p (obj&.m &&= 7)
