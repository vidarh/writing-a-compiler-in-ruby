begin
  raise(Exception)
rescue Exception => e
  p e.class
end
