s = "hi"
p s&.upcase
n = nil
p n&.upcase
def it3; yield; end
it3 do
  x = "yo"
  p x&.size
  y = nil
  p y&.size
end
