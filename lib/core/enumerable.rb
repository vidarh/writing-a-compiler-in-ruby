# Enumerable module implementation
module Enumerable
  def all?
    self.each do |item|
#      unless yield(item)
#        return false
#      end
    end
    return true
  end


  def any?
    self.each do |item|
      if yield(item)
        return true
      end
    end
    return false
  end


  def collect
    items = Array.new
    self.each do |item|
      items << yield(item)
    end
    return items
  end


  def detect(ifnone = nil)
    self.each do |item|
      if yield(item)
        return item
      end
    end
    if ifnone
      return ifnone.call
    end
    return nil
  end


  def each_cons(n)
    items = self.to_a
    ilength = items.length
    if ilength > n
      max_pairs = ilength.div(n)

      max_pairs.times do |i|
        yield(items[i..(i+n)])
      end
    end
  end


  # Iterates the given block for each slice of <n> elements.
  #
  # e.g.
  # (1..10).each_slice(3) {|a| p a}
  #   # outputs below
  #   [1, 2, 3]
  #   [4, 5, 6]
  #   [7, 8, 9]
  #   [10]
  def each_slice
    # needs to be implemented
  end


  def each_with_index
    i = 0
    self.each do |item|
      yield(item, i)
      i += 1
    end
  end


  def entries
    return self.to_a
  end


#   def enum_cons
#   end

#   def enum_slice
#   end

#   def enum_with_index
#   end


  def find(ifnone = nil, &block)
    return self.detect(ifnone, &block)
  end


  def find_all
    found = Array.new
    self.each do |item|
      if yield(item)
        found << item
      end
    end
    return found
  end


#   def grep
#   end


  def include?(obj)
    return self.any?{ |item| item == obj }
  end


  def inject(initial = nil, &block)
#    unless initial
#      return self[1..-1].inject(self.first, &block)
#    end

    acc = initial
    self.each do |item|
      acc = yield(acc, item)
    end
    return acc
  end


  alias map collect


  def max
    result = nil
    seen = false
    each do |x|
      if !seen
        result = x
        seen = true
      elsif (x <=> result) > 0
        result = x
      end
    end
    result
  end


  alias member? include?


  def min
    result = nil
    seen = false
    each do |x|
      if !seen
        result = x
        seen = true
      elsif (x <=> result) < 0
        result = x
      end
    end
    result
  end


  def count
    n = 0
    each {|x| n = n + 1 }
    n
  end


  def partition
    yes = Array.new
    no  = Array.new
    each do |x|
      if yield(x)
        yes << x
      else
        no << x
      end
    end
    [yes, no]
  end


  def reject
    items = Array.new
    self.each do |item|
      if !yield(item)
        items << item
      end
    end
    return items
  end


  def select
    items = Array.new
    self.each do |item|
      if yield(item)
        items << item
      end
    end
    return items
  end


  def sort
    a = Array.new
    each {|x| a << x }
    a.sort
  end


  def sort_by &block
    pairs = Array.new
    each {|x| pairs << [block.call(x), x] }
    sorted = pairs.sort {|a, b| a[0] <=> b[0] }
    sorted.map {|p| p[1] }
  end


  def to_a
    a = Array.new
    each {|x| a << x }
    a
  end


  def to_set
    Set.new(self)
  end


  def zip *others
    result = Array.new
    i = 0
    each do |x|
      row = [x]
      others.each {|o| row << o[i] }
      result << row
      i = i + 1
    end
    result
  end
end
