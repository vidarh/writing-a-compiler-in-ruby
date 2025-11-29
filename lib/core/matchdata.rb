# MatchData class - stores the result of a successful regexp match
class MatchData
  # Initialize with match information
  # @param regexp [Regexp] the regexp that was matched
  # @param string [String] the string that was matched against
  # @param match_start [Integer] start position of match
  # @param match_end [Integer] end position of match
  # @param captures [Array] array of captured groups (empty for now)
  def initialize(regexp, string, match_start, match_end, captures = nil)
    @regexp = regexp
    @string = string
    @match_start = match_start
    @match_end = match_end
    @captures = captures
    if @captures.nil?
      @captures = []
    end
  end

  # The entire matched string or capture group by index/name
  def [](index)
    if index == 0
      # Build substring manually since String#[start, length] not supported
      result = ""
      i = @match_start
      while i < @match_end
        result << @string[i]
        i = i + 1
      end
      result
    elsif index.is_a?(Integer) && index > 0
      # Return capture group by index
      if index <= @captures.length
        @captures[index - 1]
      else
        nil
      end
    elsif index.is_a?(Symbol) || index.is_a?(String)
      # Named capture access
      name = index.to_s
      named_map = @regexp.named_captures
      if named_map && named_map[name]
        group_idx = named_map[name][0]  # Get first group with this name
        if group_idx && group_idx <= @captures.length
          @captures[group_idx - 1]
        else
          nil
        end
      else
        nil
      end
    else
      nil
    end
  end

  # Beginning position of match (or capture group)
  def begin(n = 0)
    if n == 0
      @match_start
    else
      nil  # Capture groups not yet supported
    end
  end

  # End position of match (or capture group)
  def end(n = 0)
    if n == 0
      @match_end
    else
      nil  # Capture groups not yet supported
    end
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
