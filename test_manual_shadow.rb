def test
  [[1,2]].each do |arr|
    arr_s = arr
    arr_s.each {|x| puts arr_s.length }
  end
end

test
