def check
  super_class = Class.new do
    def a(arg)
      arg
    end
  end
  klass = Class.new super_class do
    define_method :a do |arg|
      super
    end
  end
  begin
    p klass.new.a(:a_called)
  rescue => e
    puts "#{e.class}: #{e.message}"
  end
end
check
puts "done"
