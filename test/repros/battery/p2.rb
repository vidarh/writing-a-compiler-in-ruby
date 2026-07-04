def m; yield; end
p(m { |&b| b.inspect })
