[[1]].each do |arr|
  arr_shadow = arr
  puts "Before nested:"
  puts arr_shadow.length
  arr_shadow.each {|x|
    puts "In nested:"
    puts arr_shadow.length
  }
end
