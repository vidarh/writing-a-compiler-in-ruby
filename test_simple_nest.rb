def test
  [[1]].each do |arr|
    arr.each {|x| puts arr.length }
  end
end
