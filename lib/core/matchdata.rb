# MatchData class - stores the result of a successful regexp match
class MatchData
  # Initialize with match information
  # @param regexp [Regexp] the regexp that was matched
  # @param string [String] the string that was matched against
  # @param match_start [Integer] start position of match
  # @param match_end [Integer] end position of match
  # @param captures [Array] array of captured groups (empty for now)
  def initialize(regexp, string, match_start, match_end, captures = nil, begins = nil, ends = nil)
    @regexp = regexp
    @string = string
    @match_start = match_start
    @match_end = match_end
    @captures = captures
    if @captures.nil?
      @captures = []
    end
    # Per-group begin/end char offsets (parallel to @captures), for #begin/#end/#offset.
    @begins = begins.nil? ? [] : begins
    @ends = ends.nil? ? [] : ends
  end

  # The whole matched substring (group 0). Kept separate so to_s/to_a/[0] don't recurse through #[].
  def __whole_match
    result = ""
    i = @match_start
    while i < @match_end
      result << @string[i]
      i = i + 1
    end
    result
  end

  # Value of group `index` (0 = whole match; negative counts from the end of to_a); nil if out of range.
  def __group_value(index)
    return __whole_match if index == 0
    if index > 0
      return index <= @captures.length ? @captures[index - 1] : nil
    end
    a = to_a
    a[a.length + index]
  end

  # m[i] / m[name] -> a single group; m[start, length] / m[range] -> an Array of groups (like Array#[]).
  def [](*args)
    if args.length == 1
      idx = args[0]
      if idx.is_a?(Integer)
        __group_value(idx)
      elsif idx.is_a?(Symbol) || idx.is_a?(String)
        gi = __group_index(idx)
        gi.nil? ? nil : __group_value(gi)
      elsif idx.is_a?(Range)
        to_a[idx]
      else
        nil
      end
    else
      to_a[args[0], args[1]]
    end
  end

  # Values of the given group references (integers or names).
  def values_at(*indices)
    indices.map { |i| self[i] }
  end

  # Beginning position of match (or capture group)
  # Resolve a group reference (Integer index, or a Symbol/String name) to a positional index.
  def __group_index(n)
    return n if n.is_a?(Integer)
    nm = @regexp.named_captures
    (nm && nm[n.to_s]) ? nm[n.to_s][0] : nil
  end

  def begin(n = 0)
    n = __group_index(n)
    return nil if n.nil?
    return @match_start if n == 0
    @begins[n - 1]
  end

  # End position of match (or capture group)
  def end(n = 0)
    n = __group_index(n)
    return nil if n.nil?
    return @match_end if n == 0
    @ends[n - 1]
  end

  # offset(n) -> [begin(n), end(n)] (nil pair for an unmatched group).
  def offset(n = 0)
    b = self.begin(n)
    return [nil, nil] if b.nil?
    [b, self.end(n)]
  end

  # Number of captures
  def length
    @captures.length + 1  # +1 for the full match
  end

  alias size length

  # Array of captures (including full match at index 0)
  def captures
    @captures.dup
  end

  # Convert to array (full match + captures)
  def to_a
    result = []
    result << self[0]
    @captures.each do |c|
      result << c
    end
    result
  end

  # Return the matched string
  def to_s
    self[0]
  end

  # Inspection
  def inspect
    "#<MatchData #{self[0].inspect}>"
  end

  # Pre-match (string before match)
  def pre_match
    result = ""
    i = 0
    while i < @match_start
      result << @string[i]
      i = i + 1
    end
    result
  end

  # Post-match (string after match)
  def post_match
    result = ""
    i = @match_end
    slen = @string.length
    while i < slen
      result << @string[i]
      i = i + 1
    end
    result
  end

  # The original string
  def string
    @string.dup
  end

  # The regexp used
  def regexp
    @regexp
  end

  # Named capture names from the regexp
  def names
    @regexp ? @regexp.names : []
  end

  # Named captures with their matched values
  def named_captures
    result = {}
    if @regexp
      nc = @regexp.named_captures
      nc.each do |name, indices|
        idx = indices[0]
        if idx && idx <= @captures.length
          result[name] = @captures[idx - 1]
        else
          result[name] = nil
        end
      end
    end
    result
  end
end
