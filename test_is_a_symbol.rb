x = :foo
puts "x.is_a?(Symbol) = #{x.is_a?(Symbol)}"

y = [:foo]
puts "y.is_a?(Symbol) = #{y.is_a?(Symbol)}"
puts "y.is_a?(Array) = #{y.is_a?(Array)}"
