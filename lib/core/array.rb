# -*- coding: utf-8 -*-

class Array
  # FIXME: still need to make including modules work
  # include Enumerable

  # Let's start with the basics:

  # FIXME: initialize should take two optional arguments,
  # but we don't yet handle initializers, so not supporting that
  # for now.
  def initialize *elements
    # FIXME: See notes in lib/core/core.rb regarding bootstrapping
    # of splat handling, which causes the annoyance below:
    #
    # This would work better/be simpler with tagger pointers, as in
    # that case, using Fixnum would not trigger object creation.
    # A cleaner option (over using low level stuff in Array) may be
    # to not use Fixnum#new in __get_fixnum, but wire that up specially.
    #
    # We'd still be limited in what to do here, but not as strictly.
    #
    __initialize
    if elements.length > 0
      __grow(elements[0].__get_raw)
    end
  end

  def capacity
    %s(__get_fixnum @capacity)
  end

  #FIXME: Private. Assumes idx < @len && idx >= 0
  def __get(idx)
    %s(index @ptr idx)
  end

  # --------------------------------------------------

  # Set Intersection.
  # Returns a new array containing elements common to the two arrays, with no duplicates.
#  def &(other_array)
#    return self.uniq.select{|item| other_array.include?(item)}
#  end

  # Repetition.
  # With a String argument, equivalent to self.join(str).
  # Otherwise, returns a new array built by concatenating the int copies of self.
#  def *(amount)
#    if amount.is_a?(String)
#      return self.join(amount)
#    elsif amount.is_a?(Fixnum)
#      mul_array = Array.new(self)
#      amount.times do
#        mul_array += self
#      end
#      return mul_array
#    end
#  end


  # Concatenation.
  # Returns a new array built by concatenating the two arrays together
  # to produce a third array.
#  def +(other_array)
#    added = Array.new(self)
#    other_array.each do |item|
#      added << item
#    end
#    return added
#  end

  # Array Difference.
  # Returns a new array that is a copy of the original array,
  # removing any items that also appear in other_array.
  # (If you need set-like behavior, see the library class Set.)
#  def -(other_array)
#    return self.reject{|item| other_array.include?(item)}
#  end

  # Pushes the given object on to the end of this array. This expression
  # returns the array itself, so several appends may be chained together.
  def <<(obj)
    %s(if (le @len @capacity) (callm self __grow ((mul (add @len 1) 2))))
    %s(assign (index @ptr @len) obj)
    %s(assign @len (add @len 1))
    self
  end


  # Comparison.
  # Returns an integer (-1, 0, or +1) if this array is less than, equal to,
  # or greater than other_array.
  # Each object in each array is compared (using <=>).
  # If any value isn‘t equal, then that inequality is the return value.
  # If all the values found are equal, then the return is based on a comparison
  # of the array lengths. Thus, two arrays are ``equal’’ according to Array#<=>
  # if and only if they have the same length and the value of each element is
  # equal to the value of the corresponding element in the other array.
 # def <=>(other_array)
 #   if self.size == other_array.size
 #     self.each_index do |i|
#        cmp_val = (self[i] <=> other_array[i])
#        if cmp_val != 0
#          return cmp_val
#        end
#      end
#    else
#      return self.size <=> other_array.size
#    end
#  end


  # Equality.
  # Two arrays are equal if they contain the same number of elements and if each
  # element is equal to (according to Object.==) the corresponding element in the
  # other array.
#  def ==(other_array)
#    if self.size == other_array.size
#      self.each_index do |i|
#        unless self[i] == other_array[i]
#          return false
#        end
#      end
#      return true
#    end#
#
#    return false
#  end


  def self.[](*elements)
    a = self.new
    elements.each do |e|
      a << e
    end
    a
  end

  def [](idx)
    %s(assign idx (callm idx __get_raw))

    # return element at given index
    # FIXME: Negative indices not implemented
    # FIXME: Range support not implemented

    %s(if (lt idx 0) (return nil))

    %s(if (ge idx @len)
         (assign idx (sub @len idx))
         )

    %s(if (or (or 
               (eq @ptr 0) 
               (gt idx @len)
               ) 
           (lt idx 0))
         (return nil) 
         (do
            (assign tmp (callm self __get (idx)))
            (if (eq tmp 0) (return nil) (return tmp))
             )
         )
  end


  # Element Assignment.
  # Sets the element at index, or replaces a subarray starting at start and
  # continuing for length elements, or replaces a subarray specified by range.
  # If indices are greater than the current capacity of the array, the array grows
  # automatically. A negative indices will count backward from the end of the array.
  # Inserts elements if length is zero. If nil is used in the second and third form,
  # deletes elements from self. An IndexError is raised if a negative index points
  # past the beginning of the array. See also Array#push, and Array#unshift.
  def []=(idx, obj)
    %s(assign idx (callm idx __get_raw))
    # assign position/range at given index with object/array
#    if idx < 0
#      idx = @len - idx
#    end
#    if idx < 0
#      # FIXME Oops. Error.
#      return nil
#    end

    %s(if (ge idx @len)

         (do
            (callm self __grow (idx))
            (assign @len (add idx 1))
            )
          )

    %s(assign (index @ptr idx) obj)
  end


  # Calculates the set of unambiguous abbreviations for the strings in self.
  # If passed a pattern or a string, only the strings matching the pattern or starting
  # with the string are considered.
  def abbrev(pattern = nil)
    %s(puts "Array#abbrev not implemented")
  end

  def slice(idx)
    # same as [](idx)
  end

  def slice(start, length)
    # same as []...
  end


  # Searches through an array whose elements are also arrays comparing obj with the
  # first element of each contained array using obj.==. Returns the first contained
  # array that matches (that is, the first associated array), or nil if no match is found.
  # See also Array#rassoc.
  def assoc(obj)
    self.each do |item|
      if item.is_a?(Array)
        if item.first == obj
          return item
        end
      end
    end

    return nil
  end


  # Returns the element at index. A negative index counts from the end of self.
  # Returns nil if the index is out of range. See also Array#[].
  # (Array#at is slightly faster than Array#[], as it does not accept ranges and so on.)
  def at(idx)
    # faster implementation here? or simply:
    return self[idx]
  end


  # Removes all elements from self.
  def clear
    %s(puts "Array#clear not implemented")
  end


  # Invokes the block once for each element of self, replacing the element with the value
  # returned by block.
  # See also Enumerable#collect.
  def collect!
    # replace all elements with new ones by calling block on each
  end


  # Returns a copy of self with all nil elements removed.
  def compact
    return self.reject{|item| item.nil?}
  end


  # Removes nil elements from array. Returns nil if no changes were made.
  def compact!
    %s(puts "Array#compact! not implemented")
  end

  # Appends the elements in other_array to self.
  def concat(other_array)
    # FIXME: This is wrong; concat mutates the array
    return self + other_array
  end


  def dclone
    %s(puts "Array#dclone not implemented")
  end


  # Deletes items from self that are equal to obj.
  # If the item is not found, returns nil. If the optional code block is given,
  # returns the result of block if the item is not found.
  def delete(obj)
    %s(puts "Array#delete not implemented")
  end


  # Deletes the element at the specified index, returning that element,
  # or nil if the index is out of range. See also Array#slice!.
  def delete_at(idx)
    %s(puts "Array#delete_at not implemented")
  end


  # Deletes every element of self for which block evaluates to true.
  def delete_if
    %s(puts "Array#delete_if not implemented")
  end

  def dup
    a = self.class.new
    each do |e|
      a << e
    end
    a
  end

  # Calls block once for each element in self,
  # passing that element as a parameter.
  def each &block
    i = 0
    a = block.arity
    s = self.size

    if a == 1
      while i < s
        el = self[i]
        yield(el)
        i += 1
      end
      return nil
    end

    while i < s
      el = self[i]
      if el.is_a?(Array)
        yield(*el)
      else
        yield(el)
      end
      i += 1
    end
    return nil
  end


  def member?(val)
    self.each do |v|
      return true if v == val
    end
    return false
  end


  # Same as Array#each, but passes the index of the element
  # instead of the element itself.
  def each_index
    i = 0
    while i < self.size
      yield(i)
      i += 1
    end
  end

  # Returns true if self array contains no elements.
  def empty?
    return self.size == 0
  end


  # Returns true if array and other are the same object,
  # or are both arrays with the same content.
  def eql?(other_array)
    %s(puts "Array#eql? not implemented")
  end


  # Tries to return the element at position index.
  # If the index lies outside the array, the first form throws an IndexError
  # exception, the second form returns default, and the third form returns
  # the value of invoking the block, passing in the index. Negative values of
  # index count from the end of the array.
  def fetch(idx, default = nil)
    %s(puts "Array#fetch not implemented")
  end


  def fill(obj)
    %s(puts "Array#fill not implemented")
  end


  # Returns the first element, or the first n elements, of the array.
  # If the array is empty, the first form returns nil, and the second form returns an empty array.
  def first(n = nil)
    if n
      if self.empty?
        return Array.new
      end

      first_n = Array.new
      if n >= self.size
        return Array.new(self)
      end

      n.times do |i|
        first_n << self[i]
      end
      return first_n
    end

    if self.empty?
      return nil
    else
      return self[0]
    end
  end


  # Returns a new array that is a one-dimensional flattening of this array (recursively).
  # That is, for every element that is an array, extract its elements into the new array.
  def flatten
    %s(puts "Array#flatten not implemented")
  end


  # Flattens self in place. Returns nil if no modifications were made.
  # (i.e., array contains no subarrays.)
  def flatten!
    %s(puts "Array#flatten! not implemented")
  end


  # Return true if this array is frozen (or temporarily frozen while being sorted).
  def frozen?
    %s(puts "Array#frozen? not implemented")
  end


  # Compute a hash-code for this array. Two arrays with the same content will have
  # the same hash code (and will compare using eql?).
  def hash
    %s(puts "Array#hash not implemented")
  end


  # Returns the index of the first object in self such that is == to obj.
  # Returns nil if no match is found.
  def index(obj)
    self.each_with_index do |item, idx|
      if item == obj
        return index
      end
    end

    return nil
  end


  # Replaces the contents of self with the contents of other_array,
  # truncating or expanding if necessary.
  def replace(other_array)
    %s(puts "Array#replace not implemented")
  end


  # Inserts the given values before the element with the given index
  # (which may be negative).
  def insert(idx, obj)
    %s(puts "Array#insert not implemented")
  end


  # Create a printable version of array.
  def inspect
    str = "["
    first = true
    each do |a|
      if !first
        str << ", "
      else
        first = false
      end
      str << a.inspect
    end
    str << "]"
    str
  end


  # Returns a string created by converting each element of the array to a string,
  # separated by sep.
  def join(sep) # = nil)
    join_str = ""
    size = self.size
    sep = sep.to_s
    self.each do |item|
      puts item

      if !join_str.empty?
        join_str << sep
      end
      join_str << item.to_s
    end
    join_str
  end


  # Returns the last element(s) of self.
  # If the array is empty, the first form returns nil.
  def last(n = nil)
    if n
      if n >= self.size
        return Array.new(self)
      end

      last_n = Array.new
      delta = self.size - n
      n.times do |i|
        last_n << self[i + delta]
      end
      return last_n
    end

    if self.empty?
      return nil
    else
      return self[-1]
    end
  end


  # Returns the number of elements in self. May be zero.
  def length
    %s(__get_fixnum @len)
  end


  # Invokes block once for each element of self.
  # Creates a new array containing the values returned by the block.
  # See also Enumerable#collect.
  def collect!
    %s(puts "Array#collect! not implemented")
  end


  # Invokes block once for each element of self.
  # Creates a new array containing the values returned by the block.
  # See also Enumerable#collect.
  def map!
    %s(puts "Array#map! not implemented")
  end


  # Returns the number of non-nil elements in self. May be zero.
  def nitems
    return self.select{|item| item != nil}.size
  end


  def pack
    %s(puts "Array#pack not implemented")
  end


  # Removes the last element from self and returns it,
  # or nil if the array is empty.
  def pop
    if self.empty?
      return nil
    else
      last_element = self.last
      self.delete(last_element)
      return last_element
    end
  end


  def pretty_print(q)
    %s(puts "Array#pretty_print not implemented")
  end


  # Append.
  # Pushes the given object(s) on to the end of this array.
  # This expression returns the array itself, so several appends may be chained together.
  def push(objects) # FIXME: * objects
    self << objects
  end


  def quote
    %s(puts "Array#quote not implemented")
  end


  # Searches through the array whose elements are also arrays.
  # Compares key with the second element of each contained array using ==.
  # Returns the first contained array that matches. See also Array#assoc.
  def rassoc(key)
    self.each do |item|
      if item.is_a?(Array)
        if item[1] == key
          return item
        end
      end
    end

    return nil
  end


  # Equivalent to Array#delete_if, deleting elements from self for which the
  # block evaluates to true, but returns nil if no changes were made.
  # Also see Enumerable#reject.
  def reject!
    %s(puts "Array#reject! not implemented")
  end


  # Replaces the contents of self with the contents of other_array,
  # truncating or expanding if necessary.
  def replace(other_array)
    %s(puts "Array#replace not implemented")
  end


  # Returns a new array containing self‘s elements in reverse order.
  def reverse
    %s(puts "Array#reverse not implemented")
  end


  # Reverses self in place.
  def reverse!
    %s(puts "Array#reverse! not implemented")
  end


  # Same as Array#each, but traverses self in reverse order.
  def reverse_each(&block)
    self.reverse.each(&block)
  end


  # Returns the index of the last object in array == to obj. Returns nil if no match is found.
  def rindex(obj)
    # self.reverse.index(obj) # this might be faster:
    found_index = nil
    self.each_with_index do |item, idx|
      if item == obj
        found_index = idx
      end
    end
    return found_index
  end


  # Returns the first element of self and removes it (shifting all other elements down by one).
  # Returns nil if the array is empty.
  def shift
    if self.empty?
      return nil
    else
      first_element = self.first
      self.delete_at(0)
      return first_element
    end
  end


  # Alias for length
  def size
    return self.length
  end


  # Returns a new array created by sorting self.
  # Comparisons for the sort will be done using the <=> operator or using
  # an optional code block. The block implements a comparison between a and b,
  # returning -1, 0, or +1.
  # See also Enumerable#sort_by.
  def sort
    %s(puts "Array#sort not implemented")
  end


  # Sorts self. Comparisons for the sort will be done using the <=> operator
  # or using an optional code block. The block implements a comparison between
  # a and b, returning -1, 0, or +1.
  # See also Enumerable#sort_by.
  def sort!
    %s(puts "Array#sort! not implemented")
  end


  # Returns self.
  # If called on a subclass of Array, converts the receiver to an Array object.
  def to_a
    return self
  end


  # Returns self.
  def to_ary
    return self
  end


  # Returns self.join.
  def to_s
    self.join("")
  end


  def to_yaml
    %s(puts "Array#to_yaml not implemented")
  end


  # Assumes that self is an array of arrays and transposes the rows and columns.
  def transpose
    %s(puts "Array#transpose not implemented")
  end


  # Returns a new array by removing duplicate values in self.
  def uniq
    uniq_arr = Array.new
    self.each do |item|
#      unless uniq_arr.include?(item)
#        uniq_arr << item
#      end
    end
  end


  # Removes duplicate elements from self.
  # Returns nil if no changes are made (that is, no duplicates are found).
  def uniq!
    uniq_arr = self.uniq
    changes_made = uniq_arr.size != self.size
    self = self.uniq

    if changes_made
      return self
    else
      return nil
    end
  end


  # Prepends objects to the front of array. other elements up one.
  def unshift(*objects)
    %s(puts "Array#unshift not implemented")
  end


  # Returns an array containing the elements in self corresponding to the given selector(s).
  # The selectors may be either integer indices or ranges.
  # See also Array#select.
  def values_at
    %s(puts "Array#values_at not implemented")
  end


  def yaml_initialize
    %s(puts "Array#yaml_initialize not implemented")
  end


  # Converts any arguments to arrays, then merges elements of self with corresponding
  # elements from each argument. This generates a sequence of self.size n-element arrays,
  # where n is one more that the count of arguments. If the size of any argument is less
  # than enumObj.size, nil values are supplied. If a block given, it is invoked for each
  # output array, otherwise an array of arrays is returned.
  def zip(*args)
    %s(puts "Array#zip not implemented")
  end


  # Set Union.
  # Returns a new array by joining this array with other_array, removing duplicates.
#  def |(other_array)
#    return (self + other_array).uniq
#  end
end
