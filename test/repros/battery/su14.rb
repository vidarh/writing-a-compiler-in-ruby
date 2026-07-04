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

  l = -> { klass.new.a(:a_called) }
  begin
    l.call
  rescue => e
    puts "#{e.class}: #{e.message}"
  end
end
check
puts "done"
