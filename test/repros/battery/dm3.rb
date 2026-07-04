class K5; end
r = K5.send(:define_method, :greet) do |n| n end
p r
p $__defined_methods ? $__defined_methods.size : :no_global
h = $__defined_methods[K5]
p h ? h.keys : :no_class_entry
p K5.__find_defined_method(:greet) ? :found : :not_found
