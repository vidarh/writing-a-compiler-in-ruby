
# Regexp class - Phase 0 implementation
# This provides basic Regexp functionality without actual matching support

class Regexp
  # Regexp option constants
  IGNORECASE = 1
  EXTENDED = 2
  MULTILINE = 4
  FIXEDENCODING = 16
  NOENCODING = 32

  attr_reader :source

  def initialize(pattern, options = 0)
    if pattern.is_a?(Regexp)
      @source = pattern.source
      @options = pattern.options
    else
      @source = pattern.to_s
      @options = options.is_a?(Integer) ? options : parse_options(options)
    end
  end

  # Parse string options like "im" into integer
  def parse_options(opt_str)
    return 0 if opt_str.nil?
    opts = 0
    opt_str.to_s.each_char do |c|
      case c
      when 'i' then opts |= IGNORECASE
      when 'm' then opts |= MULTILINE
      when 'x' then opts |= EXTENDED
      end
    end
    opts
  end

  def options
    @options || 0
  end

  # Match regexp against string
  # Phase 2: Supports literal matching plus basic metacharacters (. ^ $)
  def =~(string)
    return nil if string.nil?
    text = string.to_s
    tlen = text.length

    # Handle empty pattern
    return 0 if @source.length == 0

    # Check for start anchor
    anchored_start = (@source[0] == 94)  # '^'
    # Check for end anchor
    anchored_end = (@source[@source.length - 1] == 36)  # '$'

    # If anchored at start, only try position 0
    if anchored_start
      result = match_at(text, 0, tlen)
      return result ? 0 : nil
    end

    # Try matching at each position
    i = 0
    while i <= tlen
      result = match_at(text, i, tlen)
      return i if result
      i += 1
    end
    nil
  end

  # Try to match pattern at position pos in text
  # Returns true if match succeeds, false otherwise
  def match_at(text, pos, tlen)
    pattern = @source
    plen = pattern.length
    pi = 0  # pattern index
    ti = pos  # text index

    # Skip start anchor if present
    if pi < plen && pattern[pi] == 94  # '^'
      # Start anchor - must be at position 0
      return false if pos != 0
      pi += 1
    end

    while pi < plen
      pc = pattern[pi]  # pattern character code

      # Check for end anchor
      if pc == 36  # '$'
        # End anchor - must be at end of string
        return ti == tlen
      end

      # Handle escape sequences
      if pc == 92  # '\'
        pi += 1
        return false if pi >= plen  # Incomplete escape
        ec = pattern[pi]  # escaped char
        return false if ti >= tlen

        # Handle special escapes
        if ec == 100  # 'd' - digit
          return false unless char_digit?(text[ti])
        elsif ec == 68  # 'D' - non-digit
          return false if char_digit?(text[ti])
        elsif ec == 119  # 'w' - word char
          return false unless char_word?(text[ti])
        elsif ec == 87  # 'W' - non-word char
          return false if char_word?(text[ti])
        elsif ec == 115  # 's' - whitespace
          return false unless char_space?(text[ti])
        elsif ec == 83  # 'S' - non-whitespace
          return false if char_space?(text[ti])
        else
          # Escaped character - match literally
          return false if text[ti] != ec
        end
        ti += 1
        pi += 1

      # Handle '[' - character class
      elsif pc == 91  # '['
        return false if ti >= tlen
        pi += 1
        # Check for negation
        negated = false
        if pi < plen && pattern[pi] == 94  # '^'
          negated = true
          pi += 1
        end
        # Find matching ']' and check if char matches
        matched = false
        tc = text[ti]
        while pi < plen && pattern[pi] != 93  # ']'
          cc = pattern[pi]
          # Check for range a-z
          if pi + 2 < plen && pattern[pi + 1] == 45  # '-'
            range_end = pattern[pi + 2]
            if range_end != 93  # not ']'
              if tc >= cc && tc <= range_end
                matched = true
              end
              pi += 3
              next
            end
          end
          # Single character
          if tc == cc
            matched = true
          end
          pi += 1
        end
        pi += 1 if pi < plen  # skip ']'
        # Apply negation
        matched = !matched if negated
        return false unless matched
        ti += 1

      # Handle '.' - any character except newline
      elsif pc == 46  # '.'
        return false if ti >= tlen
        # '.' matches any char except newline (10)
        return false if text[ti] == 10
        ti += 1
        pi += 1
      else
        # Literal character
        return false if ti >= tlen
        return false if text[ti] != pc
        ti += 1
        pi += 1
      end
    end

    # Pattern exhausted - success
    true
  end

  # Helper: is character a digit (0-9)?
  def char_digit?(c)
    c >= 48 && c <= 57  # '0'-'9'
  end

  # Helper: is character a word char (a-z, A-Z, 0-9, _)?
  def char_word?(c)
    (c >= 97 && c <= 122) ||  # a-z
    (c >= 65 && c <= 90) ||   # A-Z
    (c >= 48 && c <= 57) ||   # 0-9
    c == 95                    # _
  end

  # Helper: is character whitespace?
  def char_space?(c)
    c == 32 || c == 9 || c == 10 || c == 13 || c == 12  # space, tab, newline, CR, FF
  end

  # Match method - returns MatchData or nil
  # Stub: Returns nil (regexp matching not yet implemented)
  def match(string, pos = 0)
    nil
  end

  # match? returns boolean
  # Stub: Returns false (regexp matching not yet implemented)
  def match?(string, pos = 0)
    false
  end

  # === for case expressions
  def ===(string)
    !!(self =~ string)
  end

  # Equality
  def ==(other)
    return false unless other.is_a?(Regexp)
    @source == other.source && options == other.options
  end
  def eql?(other)
    self == other
  end

  def hash
    @source.hash ^ options.hash
  end

  # Inspection methods
  def inspect
    flags = option_flags_string
    "/#{escape_forward_slashes(@source)}/#{flags}"
  end

  def to_s
    flags = option_flags_string
    neg_flags = negative_flags_string
    if flags.empty? && neg_flags.empty?
      "(?-mix:#{@source})"
    elsif neg_flags.empty?
      "(?#{flags}:#{@source})"
    else
      "(?#{flags}-#{neg_flags}:#{@source})"
    end
  end

  # Helper to escape forward slashes that aren't already escaped
  def escape_forward_slashes(str)
    result = ""
    i = 0
    while i < str.length
      c = str[i]
      # str[i] returns an Integer (character code), so compare against ord values
      if c == 92  # backslash '\'
        # Keep escape sequences as-is
        result << c
        i += 1
        result << str[i] if i < str.length
      elsif c == 47  # forward slash '/'
        # Escape unescaped forward slashes
        result << 92  # backslash
        result << 47  # forward slash
      else
        result << c
      end
      i += 1
    end
    result
  end

  # Build flags string from options
  def option_flags_string
    flags = ""
    flags << "m" if (options & MULTILINE) != 0
    flags << "i" if (options & IGNORECASE) != 0
    flags << "x" if (options & EXTENDED) != 0
    flags << "n" if (options & NOENCODING) != 0
    flags
  end

  # Build negative flags string for to_s
  def negative_flags_string
    flags = ""
    flags << "m" if (options & MULTILINE) == 0
    flags << "i" if (options & IGNORECASE) == 0
    flags << "x" if (options & EXTENDED) == 0
    flags
  end

  # Option query methods
  def casefold?
    (options & IGNORECASE) != 0
  end

  def fixed_encoding?
    (options & FIXEDENCODING) != 0
  end

  # Encoding - stub
  def encoding
    Encoding::US_ASCII
  end

  # Named captures - stubs returning empty
  def names
    []
  end

  def named_captures
    {}
  end

  # Class methods

  # Escape metacharacters in string
  def self.escape(str)
    result = ""
    str.to_s.each_char do |c|
      case c
      when '.', '?', '*', '+', '^', '$', '[', ']', '\\', '(', ')', '{', '}', '|', '-', ' '
        result << "\\" << c
      when "\n"
        result << "\\n"
      when "\r"
        result << "\\r"
      when "\f"
        result << "\\f"
      when "\t"
        result << "\\t"
      else
        result << c
      end
    end
    result
  end

  def self.quote(str)
    escape(str)
  end

  def self.compile(pattern, options = 0)
    new(pattern, options)
  end

  def self.union(*patterns)
    # Handle array argument
    if patterns.length == 1 && patterns[0].is_a?(Array)
      patterns = patterns[0]
    end
    return Regexp.new("(?!)") if patterns.empty?
    source = patterns.map { |p|
      if p.is_a?(Regexp)
        p.source
      else
        escape(p.to_s)
      end
    }.join("|")
    new(source)
  end

  def self.try_convert(obj)
    return obj if obj.is_a?(Regexp)
    return nil unless obj.respond_to?(:to_regexp)
    obj.to_regexp
  end

  # Last match - stub
  # Note: $~ is a global variable that should be set by match operations
  def self.last_match(n = nil)
    # Stub - would return $~ or $~[n]
    nil
  end
end
