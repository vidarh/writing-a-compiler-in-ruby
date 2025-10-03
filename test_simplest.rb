def test
  [[1]].each do |arr|
    x = arr
    x.each {|y| puts x.length }
  end
end

test
