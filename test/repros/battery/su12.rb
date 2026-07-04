class SA
  def a(arg); arg; end
end
class SB < SA
  define_method :a do |arg|
    super
  end
end
begin
  p SB.new.a(:x)
rescue RuntimeError => e
  puts "RuntimeError: #{e.message}"
rescue => e
  puts "#{e.class}: #{e.message}"
end
puts "done"
