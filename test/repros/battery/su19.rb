def check
  super_class = Class.new do
    def a(arg); arg; end
  end
  klass = Class.new super_class do
    define_method :a do |arg|
      arg
    end
  end
  i = klass.new
  %s(dprintf 2 "inst=%p inst[0]=%p klass=%p sc=%p klass[3]=%p sc[3]=%p Object=%p Class=%p\n" i (index i 0) klass super_class (index klass 3) (index super_class 3) Object Class)
  p i.a(:ok)
end
check
puts "done"
