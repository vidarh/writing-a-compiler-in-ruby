def it3; yield; end
it3 do
  ((a, b), c), (d, (e,), (f, (g, h))) = 1
  p [a, b, c, d, e, f, g, h]
end
