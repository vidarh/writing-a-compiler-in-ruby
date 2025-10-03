def test
  [[1]].each do |arr|
    arr = arr  # Manual shadow
    arr.each {|x| puts arr.length }
  end
end
test
