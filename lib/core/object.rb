
class Object
  # FIXME: Should include "Kernel" here

  def respond_to?
    %s(puts "Object#respond_to not implemented")
  end

  def is_a?
    %s(puts "Object#is_a? not implemented")
  end
end
