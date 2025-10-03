def test
  [[1]].each do |arr|
    arr_shadow = arr
    arr_shadow.each {|x| puts arr_shadow.length }
  end
end
test
