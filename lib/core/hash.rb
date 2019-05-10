
class Hash

  class Deleted
    def self.eql? other
      false
    end
  end

  def initialize defval = nil
    @length   = 0
    @capacity = 4
    _alloc_data
    @first = nil
    @last  = nil
    @defval = defval
  end

  # The full version is thorny to handle this early in bootstrap, 
  # but to make code that just wants to create an empty literal 
  # Hash nicer, we do this:
  def self.[]
    Hash.new
  end

  def _alloc_data
    # FIXME: If there's a pre-existing array, resize it
    @data = Array.new(@capacity * 4)
  end

  # Bulk insert all entries found by probing from slot 'first'
  def _bulkinsert (data,first)
    @length   = 0
    cur = first
    while cur
      k = data[cur]
      if k
        # FIXME: Combining these on one line triggers bug.
        v = data[cur + 1]
        self[k] = v
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
    @capacity = @capacity * 2
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
    pos = (key.hash % @capacity) * 4
    cap = @capacity * 4

    # This should always eventually end as we require
    # @capacity to be larger than @length, which should
    # mean that there should always be at least one 
    # empty slot.
    #
    while d = @data[pos] and !key.eql?(d)
      pos = (pos + 4 % cap)
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
    limit = (@capacity * 3) / 4

    _grow if limit <= @length

    capacity_too_low if @capacity <= @length

    slot = _find_slot(key)
    new = @data[slot].nil?
    if new
      @length = @length + 1
    end

    @data[slot+1] = value
    return if !new

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

  def __delete_first
    return if !@first
    old = @first
    @first = @data[@first+2]
    if old == @last
      @last = @first
    end
    @data[old] = nil
    @data[old+1] = nil
    @data[old+2] = nil
    @data[old+3] = nil
    @length -= 1
  end

  def shift
    return nil if !@first

    slot  = @first
    key   = @data[slot]
    value = @data[slot+1]

    __delete_first
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
      if (key  = @data[slot]) && Deleted != key
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
    @data[slot]   = Deleted
    @data[slot+1] = nil
    value
  end

end
