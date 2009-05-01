
class Array < Object
  # still need to make including modules work
  include Enumerable

  # each needs to be defined in order for all of
  # Enumerable's methods to work.
  def each
  end


# should be defined in Enumerable module:
#   def include? arg
#     %s(puts "Array#include? not implemented")
#   end

#   def member? arg
#     self.include?(arg)
#   end


  def size
    %s(puts "Array#size not implemented")
  end

  def last
  end

#  def collect
#  end

  def first
  end

  def shift
  end

  def compact
  end

  def empty?
  end
end
