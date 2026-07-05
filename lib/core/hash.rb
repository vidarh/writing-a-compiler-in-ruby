


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

  def initialize defval = nil, &block
    @length   = 0
    #@deleted  = 0
    @capacity = 7
    _alloc_data
    @first = nil
    @last  = nil
    @defval = defval
    @defproc = block
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
    pos = (h % @capacity) * 4
    cap = @capacity * 4
    start = pos

    # Special handling for nil keys: check if this slot contains the nil key
    # by walking the linked list to see if it's actually populated
    if key.nil?
      return _find_nil_slot
    end

    # This should always eventually end as we require
    # @capacity to be larger than @length, which should
    # mean that there should always be at least one
    # empty slot.
    while !(d = @data[pos]).nil? and !key.eql?(d)
      pos = (pos + 4)
      if pos >= cap
        pos -= cap
      end
    end
    pos
  end

  # Special method for finding nil key slot
  # Walk the linked list since we can't distinguish nil key from empty slot
  def _find_nil_slot
    slot = @first
    while slot
      if @data[slot].nil? && @data[slot] != DELETED
        return slot
      end
      slot = @data[slot + 2]
    end
    # Not found - return a slot for insertion based on nil's hash
    h = nil.hash
    (h % @capacity) * 4
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
    # For nil keys, _find_nil_slot returns a slot from linked list or hash position
    # Check if this slot is actually in the linked list
    if key.nil?
      slot = @first
      while slot
        if @data[slot].nil? && @data[slot] != DELETED
          return true
        end
        slot = @data[slot + 2]
      end
      return false
    end
    # An occupied slot holds the key; an empty slot holds nil. Test for nil, NOT truthiness, otherwise
    # a stored `false` key (a falsy value sitting in @data[pos]) reads as an empty slot.
    !@data[pos].nil?
  end

  def include? key
    member?(key)
  end

  # Common aliases for key membership testing
  alias key? include?
  alias has_key? include?

  def empty?
    @first.nil?
  end

  # Ruby: fetch(key) -> value, or fetch(key) { |k| ... }, or fetch(key, default). Raises KeyError when the
  # key is absent and neither a block nor a default is given. Hash#fetch was missing, so specs calling it
  # hit undefined-method dispatch (a crash) instead of raising; with KeyError now defined this also lets
  # the raise_error(KeyError, ...) matcher work.
  def fetch(key, *rest)
    return self[key] if member?(key)
    return yield(key) if block_given?
    return rest[0] if rest.length > 0
    raise KeyError.new("key not found: #{key.inspect}")
  end

  def default_proc
    @defproc
  end

  def default_proc= blk
    @defproc = blk
  end

  # Value returned for a missing key: the default proc (if set) wins over the
  # static default value.
  def _default key
    if @defproc
      return @defproc.call(self, key)
    end
    @defval
  end

  def [] key
    # Handle nil keys specially since nil is also used as empty slot marker
    if key.nil?
      return member?(nil) ? @data[_find_slot(nil) + 1] : _default(nil)
    end
    pos = _find_slot(key)
    # Test the slot for nil (empty), NOT truthiness -- a stored `false` key is falsy but present.
    @data[pos].nil? ? _default(key) : @data[pos + 1]
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

  def keys
    a = []
    each do |k, v|
      a << k
    end
    a
  end

  def values
    a = []
    each do |k, v|
      a << v
    end
    a
  end

  def each
    return to_enum(:each) if !block_given?
    slot = @first
    while slot
      key = @data[slot]
      # Only skip DELETED entries, not nil keys
      # (we iterate via linked list so all slots are valid)
      if key != DELETED
        value = @data[slot + 1]
        yield key, value
      end
      slot = @data[slot + 2]
    end
  end

  # each_pair is an alias of each (yields [key, value] for each pair).
  alias each_pair each

  # store(key, value) is an alias of []=.
  def store(key, value)
    self[key] = value
  end

  # A new hash with keys and values swapped (later pairs win on duplicate values).
  def invert
    h = {}
    each { |k, v| h[v] = k }
    h
  end

  # Flatten to an array [k1, v1, k2, v2, ...]; level > 1 flattens nested array values further.
  def flatten(level = 1)
    result = []
    each { |k, v| result << k; result << v }
    level > 1 ? result.flatten(level - 1) : result
  end

  # map each pair through the block, dropping falsy results.
  def filter_map(&block)
    return to_enum(:filter_map) if !block
    result = []
    each { |k, v| r = block.call(k, v); result << r if r }
    result
  end

  # Predicates over the pairs. Without a block, any?/none? test emptiness; with a block, the block is
  # called with (key, value). (Hash does not include Enumerable in this runtime, so these are defined here.)
  def any?(&block)
    each { |k, v| return true if block ? block.call(k, v) : true }
    false
  end

  def all?(&block)
    each { |k, v| return false if block ? !block.call(k, v) : false }
    true
  end

  def none?(&block)
    each { |k, v| return false if block ? block.call(k, v) : true }
    true
  end

  def one?(&block)
    n = 0
    each { |k, v| n = n + 1 if block ? block.call(k, v) : true }
    n == 1
  end

  # More Enumerable methods, defined directly (Hash does not include Enumerable here). The block is
  # called with (key, value); without a block the pair [k, v] is used where an element value is needed.
  def sum(init = 0, &block)
    s = init
    each { |k, v| s = s + (block ? block.call(k, v) : [k, v]) }
    s
  end

  def flat_map(&block)
    return to_enum(:flat_map) if !block
    result = []
    each do |k, v|
      r = block.call(k, v)
      if r.is_a?(Array)
        r.each { |e| result << e }
      else
        result << r
      end
    end
    result
  end
  alias collect_concat flat_map

  def min_by(&block)
    return to_enum(:min_by) if !block
    best = nil
    best_v = nil
    found = false
    each do |k, v|
      val = block.call(k, v)
      if !found || val < best_v
        best = [k, v]
        best_v = val
        found = true
      end
    end
    best
  end

  def max_by(&block)
    return to_enum(:max_by) if !block
    best = nil
    best_v = nil
    found = false
    each do |k, v|
      val = block.call(k, v)
      if !found || val > best_v
        best = [k, v]
        best_v = val
        found = true
      end
    end
    best
  end

  # Pair-oriented Enumerable methods. Where a "value" is needed these use the [k, v] pair (via #to_a,
  # which yields pairs in insertion order); block forms call the block with (key, value).
  def sort(&block)
    to_a.sort(&block)
  end

  def first(n = nil)
    return to_a.first if n.nil?
    to_a.first(n)
  end

  def take(n)
    to_a.take(n)
  end

  def drop(n)
    to_a.drop(n)
  end

  def find(&block)
    return to_enum(:find) if !block
    each { |k, v| return [k, v] if block.call(k, v) }
    nil
  end
  alias detect find

  def group_by(&block)
    return to_enum(:group_by) if !block
    result = {}
    each do |k, v|
      key = block.call(k, v)
      result[key] = [] if !result.has_key?(key)
      result[key] << [k, v]
    end
    result
  end

  def partition(&block)
    return to_enum(:partition) if !block
    yes = []
    no = []
    each do |k, v|
      if block.call(k, v)
        yes << [k, v]
      else
        no << [k, v]
      end
    end
    [yes, no]
  end

  def each_with_index(&block)
    return to_enum(:each_with_index) if !block
    i = 0
    each do |k, v|
      block.call([k, v], i)
      i = i + 1
    end
    self
  end

  # A new hash of the pairs for which the block is FALSE (reject) / TRUE (select/filter).
  def reject(&block)
    return to_enum(:reject) if !block
    h = {}
    each { |k, v| h[k] = v if !block.call(k, v) }
    h
  end

  def select(&block)
    return to_enum(:select) if !block
    h = {}
    each { |k, v| h[k] = v if block.call(k, v) }
    h
  end
  alias filter select

  # In-place reject!/select!: delete the matching / non-matching pairs, returning self if anything was
  # removed and nil otherwise. delete_if/keep_if are the same walks but always return self.
  def reject!(&block)
    return to_enum(:reject!) if !block
    removed = []
    each { |k, v| removed << k if block.call(k, v) }
    removed.each { |k| delete(k) }
    removed.empty? ? nil : self
  end

  def select!(&block)
    return to_enum(:select!) if !block
    removed = []
    each { |k, v| removed << k if !block.call(k, v) }
    removed.each { |k| delete(k) }
    removed.empty? ? nil : self
  end
  alias filter! select!

  def delete_if(&block)
    return to_enum(:delete_if) if !block
    reject!(&block)
    self
  end

  def keep_if(&block)
    return to_enum(:keep_if) if !block
    select!(&block)
    self
  end

  # A new hash with only the given keys that are present.
  def slice(*keys)
    h = {}
    keys.each { |k| h[k] = self[k] if has_key?(k) }
    h
  end

  # A new hash with the given keys removed.
  def except(*keys)
    h = {}
    each { |k, v| h[k] = v if !keys.include?(k) }
    h
  end

  # Values for the given keys, raising KeyError (or yielding the block) for any missing key.
  def fetch_values(*keys, &block)
    keys.map do |k|
      if has_key?(k)
        self[k]
      elsif block
        block.call(k)
      else
        raise KeyError.new("key not found: #{k.inspect}")
      end
    end
  end

  # Nested element access: dig(a, b, ...) == self[a].dig(b, ...), stopping at the first nil.
  def dig(key, *rest)
    v = self[key]
    return v if rest.empty? || v.nil?
    v.dig(*rest)
  end

  # A new hash with the same keys and each value passed through the block.
  def transform_values(&block)
    h = {}
    each { |k, v| h[k] = block.call(v) }
    h
  end

  # In-place transform_values (returns self). Keys are snapshotted first so re-assigning values during the
  # walk is safe.
  def transform_values!(&block)
    keys.each { |k| self[k] = block.call(self[k]) }
    self
  end

  # Hash#count: no arg -> size; with a block -> number of [key, value] pairs the
  # block accepts. (Included Enumerable#count did not resolve here.)
  def count(*args, &block)
    return size if args.empty? && !block
    n = 0
    each do |k, v|
      if block
        n += 1 if block.call(k, v)
      else
        n += 1 if [k, v] == args[0]
      end
    end
    n
  end

  # A new hash with each key passed through the block (later keys win on collision).
  # MRI also accepts a mapping-hash argument (unmapped keys pass through), and both
  # can combine: the hash mapping wins, the block handles the rest.
  def transform_keys(mapping = nil, &block)
    h = {}
    each do |k, v|
      if mapping && mapping.key?(k)
        h[mapping[k]] = v
      elsif block
        h[block.call(k)] = v
      else
        h[k] = v
      end
    end
    h
  end

  # In-place transform_keys; returns self.
  def transform_keys!(mapping = nil, &block)
    replacement = transform_keys(mapping, &block)
    old_keys = keys
    old_keys.each { |k| delete(k) }
    replacement.each { |k, v| self[k] = v }
    self
  end

  # Subset/superset comparisons: every pair of the smaller hash must be present
  # (same key AND value) in the larger.
  def __subset_of?(other)
    each do |k, v|
      return false if !other.key?(k)
      return false if !(other[k] == v)
    end
    true
  end

  def <=(other)
    raise TypeError, "no implicit conversion of #{other.class} into Hash" if !other.is_a?(Hash)
    __subset_of?(other)
  end

  def <(other)
    raise TypeError, "no implicit conversion of #{other.class} into Hash" if !other.is_a?(Hash)
    length < other.length && __subset_of?(other)
  end

  def >=(other)
    raise TypeError, "no implicit conversion of #{other.class} into Hash" if !other.is_a?(Hash)
    other.__subset_of?(self)
  end

  def >(other)
    raise TypeError, "no implicit conversion of #{other.class} into Hash" if !other.is_a?(Hash)
    other.length < length && other.__subset_of?(self)
  end

  # First [key, value] pair whose key == the argument (nil if none).
  def assoc(key)
    each do |k, v|
      return [k, v] if k == key
    end
    nil
  end

  # First [key, value] pair whose VALUE == the argument (nil if none).
  def rassoc(value)
    each do |k, v|
      return [k, v] if v == value
    end
    nil
  end

  def each_key(&block)
    return keys.each if !block
    keys.each { |k| block.call(k) }
    self
  end

  def each_value(&block)
    return values.each if !block
    values.each { |v| block.call(v) }
    self
  end

  # to_h: self (a copy for subclass instances in MRI; plain dup here), or with a
  # block, a new Hash of the block's [key, value] pairs.
  def to_h(&block)
    return self if !block && self.class == Hash
    h = {}
    each do |k, v|
      if block
        pair = block.call(k, v)
        raise TypeError, "wrong element type #{pair.class} (expected array)" if !pair.is_a?(Array)
        raise ArgumentError, "element has wrong array length (expected 2, was #{pair.length})" if pair.length != 2
        h[pair[0]] = pair[1]
      else
        h[k] = v
      end
    end
    h
  end

  def self.try_convert(obj)
    return obj if obj.is_a?(Hash)
    if obj.respond_to?(:to_hash)
      r = obj.to_hash
      return r if r.is_a?(Hash) || r.nil?
      raise TypeError, "can't convert #{obj.class} to Hash (#{obj.class}#to_hash gives #{r.class})"
    end
    nil
  end

  # A copy with all nil-valued pairs removed.
  def compact
    h = {}
    each { |k, v| h[k] = v if !v.nil? }
    h
  end

  # Remove all nil-valued pairs in place; returns self if anything was removed, else nil.
  def compact!
    removed = []
    each { |k, v| removed << k if v.nil? }
    removed.each { |k| delete(k) }
    removed.empty? ? nil : self
  end

  # A proc that maps a key to its value (h.to_proc.call(k) == h[k]).
  def to_proc
    h = self
    lambda { |k| h[k] }
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
    # A nil key collides representationally with the empty-slot marker (both nil), so it
    # must be checked for membership explicitly (as #[] and #member? do) rather than via the
    # generic slot lookup: for an absent nil key, _find_nil_slot returns an arbitrary slot
    # (nil.hash % capacity) that may hold a different key, which would otherwise be deleted.
    if key.nil?
      return nil unless member?(nil)
      slot = _find_nil_slot
    else
      slot = _find_slot(key)
      return nil if !@data[slot]
    end
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

  # merge(*others) { |key, oldval, newval| ... } -> a new Hash with each other merged in. Without a
  # block, later values win; with a block, it resolves key collisions. Iteration uses keys + [] and
  # while-loops (not nested each-blocks) so the conflict `yield` happens directly in the method body,
  # avoiding the fragile yield-from-inside-a-block path.
  def merge(*others)
    result = dup
    has_block = block_given?
    i = 0
    while i < others.length
      other = others[i]
      ks = other.keys
      j = 0
      while j < ks.length
        k = ks[j]
        v = other[k]
        if has_block && result.member?(k)
          result[k] = yield(k, result[k], v)
        else
          result[k] = v
        end
        j = j + 1
      end
      i = i + 1
    end
    result
  end

  # In-place merge (also aliased as #update).
  def merge!(*others)
    has_block = block_given?
    i = 0
    while i < others.length
      other = others[i]
      ks = other.keys
      j = 0
      while j < ks.length
        k = ks[j]
        v = other[k]
        if has_block && member?(k)
          self[k] = yield(k, self[k], v)
        else
          self[k] = v
        end
        j = j + 1
      end
      i = i + 1
    end
    self
  end

  alias update merge!

  def ==(other)
    # Identity short-circuit: prevents infinite recursion (segfault) on self-referential hashes
    # (h[:k]=h; h==h), and is correct since a hash always equals itself.
    return true if self.equal?(other)
    return false if !other.is_a?(Hash)
    return false if size != other.size
    # Recursion guard: if self is already mid-comparison higher up the stack, this is a cyclic
    # (self-referential) structure -- treat the back-edge as equal so we terminate instead of
    # recursing forever (-> heap exhaustion / SIGSEGV). The flag is a plain ivar set on entry and
    # cleared on exit (no global state, which would break core bootstrap to initialise).
    return true if @__comparing
    @__comparing = true
    result = true
    each do |k, v|
      if !other.member?(k)
        result = false
      elsif other[k] != v
        result = false
      end
    end
    @__comparing = false
    result
  end

  # pair - return first key-value pair as array
  # Stub: Return first entry
  def pair
    if @first
      [@data[@first], @data[@first + 1]]
    else
      nil
    end
  end

  # hash_splat - return self for ** operator
  # Stub: Just return self
  def hash_splat
    self
  end

  # Duplicate this hash
  def dup
    result = Hash.new(@defval)
    each do |k, v|
      result[k] = v
    end
    result
  end

end
