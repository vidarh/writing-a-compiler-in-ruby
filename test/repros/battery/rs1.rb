a = raise(StandardError) rescue 1
p a
begin
  l = -> { raise(Exception) rescue 1 }
  l.call
  p "no-raise"
rescue Exception => e
  p e.class
end
p "done"
