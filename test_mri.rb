def test
  [[1]].each do |arr|
    f = lambda { puts arr.length }
    f.call
  end
end
test
