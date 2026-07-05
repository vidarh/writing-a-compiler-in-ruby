f = -> fmt, *args do
  [1].each { |x| x }
  fmt + args.length.to_s
end
r = f.call("a", 1, 2)
p r
