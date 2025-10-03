[[1]].each do |arr|
  arr = arr
  puts "Before nested:"
  puts arr.length
  arr.each {|x|
    puts "In nested:"
    puts arr.length
  }
end
