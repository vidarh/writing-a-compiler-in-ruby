
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
  # Phase 1: Literal string matching only (no metacharacters)
  def =~(string)
    return nil if string.nil?
    text = string.to_s
    pattern = @source
    plen = pattern.length
    tlen = text.length

    # Handle empty pattern
    return 0 if plen == 0

    # Simple substring search
    i = 0
    while i <= tlen - plen
      # Compare at position i
      match = true
      j = 0
      while j < plen
        # Compare character codes (str[i] returns Integer in this compiler)
        if text[i + j] != pattern[j]
          match = false
          break
        end
        j += 1
      end
      return i if match
      i += 1
    end
    nil
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
