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

  # The entire matched string
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
      # Return capture group
      if index <= @captures.length
        @captures[index - 1]
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

  def size
    length
  end

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

  # Named captures - stub
  def names
    []
  end

  def named_captures
    {}
  end
end
