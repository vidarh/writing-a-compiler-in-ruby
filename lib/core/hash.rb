
class Hash
  def initialize
    @length   = 0
    @capacity = 4
    _alloc_data
    @first = nil
    @last  = nil
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

  def [] key
    pos  = _find_slot(key)
    @data[pos] ? @data[pos + 1] : nil
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

    @length = @length + 1

    slot = _find_slot(key)

    @data[slot]   = key
    @data[slot+1] = value

    # Maintain insertion order:
    if @last
      @data[@last+2] = slot
    end
    if !@first
      @first = slot
    end
    @data[slot+3] = @last
    @last = slot

    nil
  end

  def each
    pos = 0
    capacity = @capacity * 2
    slot = @first
    while slot
      if key  = @data[slot]
        value = @data[slot + 1]
        yield key,value
      end
      slot = @data[slot + 2]
    end
  end
end
