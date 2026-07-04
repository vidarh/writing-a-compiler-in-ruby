def some_method
  Proc.new { return }
end
res = some_method
begin
  res.call
  p "no error"
rescue LocalJumpError => e
  p e.message
end
