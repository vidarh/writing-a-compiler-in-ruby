
class Object
  # FIXME: Should include "Kernel" here

  def initialize
    # Default. Empty on purpose
  end

  def respond_to?
    %s(puts "Object#respond_to not implemented")
  end

  def is_a?
    %s(puts "Object#is_a? not implemented")
  end
end
