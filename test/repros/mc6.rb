$spec_object = Object.new
l = lambda do
  constants = class << $spec_object; constants; end
  p constants
end
l.call
puts "done"
