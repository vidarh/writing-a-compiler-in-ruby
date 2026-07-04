def check
  l = lambda do |arg|
    super
  end
  begin
    l.call(1)
  rescue => e
    puts "#{e.class}: #{e.message}"
  end
end
check
puts "done"
