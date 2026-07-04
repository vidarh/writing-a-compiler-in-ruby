a = [*("!".."/")] - ["$", "*"] - ["("]
p a.length
c = "!"
r = /#{c}/
p r.class
["!", "-"].each do |ch|
  pat = eval("%r" + ch)
  p [pat, /#{ch}/.source] rescue p :rescued
end
p "done"
