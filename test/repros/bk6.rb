def t
  r = []
  [1, 2].each do |x|
    [10, 20].each do |y|
      break if y == 10
      r << y
    end
    r << x
  end
  r
end
p t
puts "done"
