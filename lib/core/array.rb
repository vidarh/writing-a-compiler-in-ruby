
class Array < Object
  def include? arg
    %s(puts "Array#include? not implemented")
  end

  def member? arg
    self.include?(arg)
  end

  def size
    %s(puts "Array#size not implemented")
  end

  def last
  end

  def collect
  end

  def first
  end

  def shift
  end

  def compact
  end

  def empty?
  end
end
