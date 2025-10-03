def test
  [[5]].each do |arr|
    puts "arr="
    puts arr.length
    arr.each {|x|
      puts "x="
      puts x
      puts "arr.length="
      puts arr.length
    }
  end
end

test
