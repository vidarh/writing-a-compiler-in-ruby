def m
  [1,2,3].each { |x| return x * 10 if x == 2 }
  :not_reached
end
p m
