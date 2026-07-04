class K7; end
begin
  K7.new.nope
rescue => e
  p e.class
end
p "after"
