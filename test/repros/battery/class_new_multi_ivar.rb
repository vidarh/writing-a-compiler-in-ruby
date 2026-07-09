# An anonymous Class.new whose initialize assigns 3+ ivars directly (not via attr_*) used to
# under-size the instance (@instance_size counted only attr ivars) -> the 3rd ivar write ran off
# the object end (free(): invalid next size). See transform.rb rewrite_class_new needed_slots.
k = Class.new do
  def initialize; @a = 1; @b = 2; @c = 3; @d = 4; end
  def sum; @a + @b + @c + @d; end
end
raise "wrong" unless k.new.sum == 10
puts "ok"
