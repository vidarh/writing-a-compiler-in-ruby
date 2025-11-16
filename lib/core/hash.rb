


class Hash

  class Deleted
    def eql? other
      false
    end

    #def self.nil?
    #  true
    #end
  end

  DELETED = Deleted.new

  def initialize defval = nil
    @length   = 0
    #@deleted  = 0
    @capacity = 7
    _alloc_data
    @first = nil
    @last  = nil
    @defval = defval
  end

  def default
    @defval
  end

  # The full version is thorny to handle this early in bootstrap, 
  # but to make code that just wants to create an empty literal 
  # Hash nicer, we do this:
  def self.[]
    self.new
  end

  def _data
    @data
  end

  def _state
    [@first, @last]
  end

  def _alloc_data
    # FIXME: If there's a pre-existing array, resize it
    @data = Array.new(@capacity * 4)
  end

  def not_deleted?(o)
    #%s(if (ne o Deleted) true false)
    o != DELETED
  end

  # Bulk insert all entries found by probing from slot 'first'
  def _bulkinsert (data,first)
    @length   = 0
    cur = first
    while cur
      k = data[cur]
      # FIXME: Check for `Deleted`?
      if k
        if not_deleted?(k)
          # FIXME: Doing k == Deleted or k != Deleted here fails.
          # FIXME: Combining these on one line triggers bug.
          v = data[cur + 1]
          self[k] = v
        end
      end
      cur = data[cur + 2]
    end
    nil
  end

  def _grow
    # Keep the old capacity and data pointer, as we need them to
    # re-insert the data later.
    oldcap   = @capacity
    olddata  = @data
    oldfirst = @first

    # Grow
    @capacity = @capacity * 4 + 1
    _alloc_data

    # For insertion order:
    @first = nil
    @last  = nil

    _bulkinsert(olddata, oldfirst)
  end

  # Linearly probe @data for a hash slot that holds
  # the matching key *or* the first one that is unoccupied
  #
  def _find_slot(key)
    h = key.hash
#    s = key.to_s
    pos = (h % @capacity) * 4
#    %s(printf "key='%s'\n" (callm s __get_raw))
#    %s(printf "hash=%ld,pos=%d\n" (callm h __get_raw) (callm pos __get_raw))
    cap = @capacity * 4




    # This should always eventually end as we require
    # @capacity to be larger than @length, which should
    # mean that there should always be at least one
    # empty slot.
    #
    #puts "START FOR KEY: #{key}"
    while !(d = @data[pos]).nil? and !key.eql?(d)
      %s(__docnt)
      pos = (pos + 4)
      if pos >= cap
        pos -= cap
      end
    end
    pos
  end

  def _find_insertion_slot(key)
    h = key.hash
    pos = (h % @capacity) * 4
    cap = @capacity * 4

    # This should always eventually end as we require
    # @capacity to be larger than @length, which should
    # mean that there should always be at least one
    # empty slot.
    #
    #puts "START FOR KEY: #{key}"
    while !(d = @data[pos]).nil? and !key.eql?(d)
      oldpos = pos
      pos = (pos + 4)
      if pos >= cap
        pos -= cap
      end

      if !not_deleted?(d)
        if @data[pos].nil?
          return oldpos
        end
      end
    end
    pos
  end

  def member? key
    pos = _find_slot(key)
    @data[pos] ? true : false
  end

  def include? key
    member?(key)
  end

  def empty?
    @first.nil?
  end

  def [] key
    pos  = _find_slot(key)
    @data[pos] ? @data[pos + 1] : @defval
  end

  def capacity_too_low
    # FIXME: This should be an exception but we don't
    # support exceptions yet
    puts "ERROR: @capacity <= @length *after* _grow"
    exit(1)
  end

  def []= key,value
    limit = @capacity / 2

    _grow if limit <= @length

    capacity_too_low if @capacity <= @length

    slot = _find_insertion_slot(key)
    new = @data[slot].nil?
    if new
      @length = @length + 1
    end

    @data[slot+1] = value
    ndel = not_deleted?(@data[slot])
    if !new
      if ndel
        return
      end
    end

    @data[slot]   = key
    # Maintain insertion order:
    if @last
      @data[@last+2] = slot
    end
    if @first.nil?
      @first = slot
    end
    @data[slot+2] = nil
    @data[slot+3] = @last
    @last = slot

    nil
  end

  def shift
    return nil if !@first

    slot  = @first
    key   = @data[slot]
    value = @data[slot+1]

    delete(key)
    [key,value]
  end

  def length
    @length
  end

  def size
    @length
  end

  def to_a
    a = []
    each do |k,v|
      a << [k,v]
    end
    a
  end

  def each
    pos = 0
    capacity = @capacity * 2
    slot = @first
    while slot
      if (key  = @data[slot]) && key != DELETED
        value = @data[slot + 1]
        yield key,value
      end
      slot = @data[slot + 2]
    end
  end

  # FIXME: This is a very crude way of handling deletion:
  # It simply removes the key by replacing it with 
  # Deleted that compares false against everyhing
  # using #eql?. The problem with this is that it will
  # gradually pollute the Hash. 
  #
  # To do this "properly" you would need to either
  # rebuild the hash completely on delete, or more
  # reasonably, continue to probe past the deletion
  # point, determine if each encountered key hashes
  # to somewhere between the current location and
  # the location being probed, and if so move it and
  # update insertion points etc..
  # 
  # As a compromise solution, at least update insertion
  # operations to insert into Deleted slots.
  def delete key
    slot  = _find_slot(key)
    return nil if !@data[slot]
    value = @data[slot+1]
    @data[slot]   = DELETED
    @data[slot+1] = nil

    # Unlink record
    n    = @data[slot+2]
    prev = @data[slot+3]
    if prev
      @data[prev+2] = n
    end
    if n
      @data[n+3] = prev
    end
    if @first == slot
      @first = n
    end
    if @last == slot
      @last = prev
    end

    # FIXME: It fails without this, which indicates a bug.
    #@length -= 1
    value
  end

  def merge(other)
    result = Hash[]
    each do |k, v|
      result[k] = v
    end
    other.each do |k, v|
      result[k] = v
    end
    result
  end

  def ==(other)
    return false if !other.is_a?(Hash)
    return false if size != other.size
    each do |k, v|
      return false if !other.member?(k)
      return false if other[k] != v
    end
    true
  end

end
