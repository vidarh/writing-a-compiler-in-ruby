def check
  klass = Class.new do
    define_method :a do |arg|
      super
    end
  end
  begin
    p klass.new.a(:x)
  rescue => e
    puts "#{e.class}: #{e.message}"
  end
end
check
puts "done"
