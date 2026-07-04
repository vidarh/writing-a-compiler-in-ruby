begin
  l = -> { raise(Exception) rescue 1 }
  p l.call
rescue Exception => e
  p e.class
end
