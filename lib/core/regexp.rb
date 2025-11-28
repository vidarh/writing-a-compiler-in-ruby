
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

  # Match regexp against string - returns position of match or nil
  # Phase 4: Supports literals, metacharacters, character classes, and basic quantifiers
  def =~(string)
    result = match_internal(string)
    result ? result[0] : nil
  end

  # Match method - returns MatchData or nil
  def match(string, pos = 0)
    return nil if string.nil?
    text = string.to_s
    if pos > 0
      # Skip first pos characters
      text = text[pos, text.length - pos]
    end
    result = match_internal(text)
    if result
      start_pos = result[0]
      end_pos = result[1]
      captures = result[2]
      # Adjust positions if we started at an offset
      if pos > 0
        start_pos = start_pos + pos
        end_pos = end_pos + pos
      end
      MatchData.new(self, string.to_s, start_pos, end_pos, captures)
    else
      nil
    end
  end

  # match? returns boolean - more efficient than match
  def match?(string, pos = 0)
    return false if string.nil?
    text = string.to_s
    if pos > 0
      text = text[pos, text.length - pos]
    end
    result = match_internal(text)
    result ? true : false
  end

  # Internal match - returns [start_pos, end_pos, captures] or nil
  def match_internal(string)
    return nil if string.nil?
    text = string.to_s
    tlen = text.length

    # Initialize capture tracking
    @match_captures = []
    @next_capture_index = 0
    @match_text = text  # Store text for capture extraction

    # Handle empty pattern
    return [0, 0, []] if @source.length == 0

    # Check for start anchor
    anchored_start = (@source[0] == 94)  # '^'

    # If anchored at start, only try position 0
    if anchored_start
      end_pos = match_at(text, 0, tlen)
      return end_pos ? [0, end_pos, @match_captures] : nil
    end

    # Try matching at each position
    i = 0
    while i <= tlen
      # Reset captures for each starting position
      @match_captures = []
      @next_capture_index = 0
      end_pos = match_at(text, i, tlen)
      if end_pos
        return [i, end_pos, @match_captures]
      end
      i += 1
    end
    nil
  end

  # Try to match pattern at position pos in text
  # Returns end position if match succeeds, nil otherwise
  def match_at(text, pos, tlen)
    match_from(@source, 0, text, pos, tlen)
  end

  # Core matching engine with backtracking support
  # Returns end text position if match succeeds, nil otherwise
  def match_from(pattern, pi, text, ti, tlen)
    plen = pattern.length

    # Handle alternation first (lowest precedence)
    # Look for top-level | (not inside groups or character classes)
    if pi == 0 && plen > 0
      alt_positions = []
      scan_i = 0
      depth = 0
      in_class = false
      while scan_i < plen
        c = pattern[scan_i]
        if c == 92  # '\' - skip escaped char
          scan_i += 1
        elsif c == 91 && !in_class  # '[' - start character class
          in_class = true
        elsif c == 93 && in_class  # ']' - end character class
          in_class = false
        elsif c == 40 && !in_class  # '(' - increase depth
          depth = depth + 1
        elsif c == 41 && !in_class  # ')' - decrease depth
          depth = depth - 1
        elsif c == 124 && depth == 0 && !in_class  # '|' at top level
          alt_positions << scan_i
        end
        scan_i = scan_i + 1
      end

      # If we have alternatives, try each one
      if alt_positions.length > 0
        # Try first alternative
        start = 0
        i = 0
        while i <= alt_positions.length
          if i < alt_positions.length
            alt_end = alt_positions[i]
          else
            alt_end = plen
          end
          # Extract alternative manually (String#[start,len] not supported)
          alt = ""
          j = start
          while j < alt_end
            alt << pattern[j]
            j = j + 1
          end
          # Try this alternative
          result = match_from(alt, 0, text, ti, tlen)
          return result if result
          start = alt_end + 1
          i = i + 1
        end
        return nil  # No alternative matched
      end
    end

    # Skip start anchor if present at beginning
    if pi == 0 && pi < plen && pattern[pi] == 94  # '^'
      pi += 1
    end

    while pi < plen
      pc = pattern[pi]  # pattern character code

      # Check for end anchor
      if pc == 36  # '$'
        return ti == tlen ? ti : nil
      end

      # Parse the current atom and check for quantifier
      atom_start = pi
      atom_end = nil

      # Handle escape sequences
      if pc == 92  # '\'
        pi += 1
        return nil if pi >= plen  # Incomplete escape
        atom_end = pi + 1

      # Handle '[' - character class
      elsif pc == 91  # '['
        pi += 1
        pi += 1 if pi < plen && pattern[pi] == 94  # skip '^'
        # Find closing ']'
        while pi < plen && pattern[pi] != 93
          pi += 1
        end
        pi += 1 if pi < plen  # skip ']'
        atom_end = pi

      # Handle '(' - group
      elsif pc == 40  # '('
        pi += 1
        # Skip special group markers like (?:, (?=, etc.
        if pi < plen && pattern[pi] == 63  # '?'
          pi += 1
          # Skip the type character (: = ! < etc)
          pi += 1 if pi < plen
        end
        # Find matching ')' with nesting
        depth = 1
        while pi < plen && depth > 0
          c = pattern[pi]
          if c == 92  # '\' - skip escaped char
            pi += 1
          elsif c == 40  # '('
            depth = depth + 1
          elsif c == 41  # ')'
            depth = depth - 1
          end
          pi += 1
        end
        atom_end = pi

      # Handle '.' or literal
      else
        atom_end = pi + 1
      end

      # Check for quantifier after atom
      # quant: 0=none, 1=star(*), 2=plus(+), 3=question(?), 4=range({n,m})
      quant = 0
      quant_min = 0
      quant_max = -1  # -1 means unlimited
      quant_lazy = false
      quant_pi = atom_end
      if quant_pi < plen
        qc = pattern[quant_pi]
        if qc == 42  # '*'
          quant = 1
          quant_min = 0
          quant_max = -1
          pi = quant_pi + 1
        elsif qc == 43  # '+'
          quant = 2
          quant_min = 1
          quant_max = -1
          pi = quant_pi + 1
        elsif qc == 63  # '?'
          quant = 3
          quant_min = 0
          quant_max = 1
          pi = quant_pi + 1
        elsif qc == 123  # '{' - range quantifier
          # Parse {n}, {n,}, or {n,m}
          save_pi = quant_pi + 1
          pi = save_pi
          # Parse first number
          n1 = 0
          has_n1 = false
          while pi < plen && pattern[pi] >= 48 && pattern[pi] <= 57
            n1 = n1 * 10 + (pattern[pi] - 48)
            has_n1 = true
            pi = pi + 1
          end
          if has_n1 && pi < plen && pattern[pi] == 125  # '}' - exact: {n}
            quant = 4
            quant_min = n1
            quant_max = n1
            pi = pi + 1
          elsif pi < plen && pattern[pi] == 44  # ','
            pi = pi + 1
            if has_n1 && pi < plen && pattern[pi] == 125  # '}' - at least: {n,}
              quant = 4
              quant_min = n1
              quant_max = -1
              pi = pi + 1
            else
              # Parse second number: {n,m}
              n2 = 0
              has_n2 = false
              while pi < plen && pattern[pi] >= 48 && pattern[pi] <= 57
                n2 = n2 * 10 + (pattern[pi] - 48)
                has_n2 = true
                pi = pi + 1
              end
              if has_n2 && pi < plen && pattern[pi] == 125  # '}'
                # Only valid if we have at least n1 or n2
                if has_n1
                  quant = 4
                  quant_min = n1
                  quant_max = n2
                  pi = pi + 1
                else
                  # {,m} - treat as {0,m}
                  quant = 4
                  quant_min = 0
                  quant_max = n2
                  pi = pi + 1
                end
              else
                # Malformed, treat { as literal
                pi = atom_end
              end
            end
          else
            # Malformed (including {}), treat { as literal
            pi = atom_end
          end
        else
          pi = atom_end
        end
      else
        pi = atom_end
      end

      # Check for ? after quantifier (makes it non-greedy/lazy)
      if quant != 0 && pi < plen && pattern[pi] == 63  # '?'
        quant_lazy = true
        pi = pi + 1
      end

      if quant != 0
        # Handle quantified atom with backtracking
        # match_quantified recursively matches the rest of the pattern,
        # so we return its result directly
        ti = match_quantified(pattern, atom_start, atom_end, quant_min, quant_max, quant_lazy, pi, text, ti, tlen)
        return ti  # Either nil (no match) or the final position (match)
      else
        # Match single atom
        ti = match_atom(pattern, atom_start, text, ti, tlen)
        return nil if ti.nil?
      end
    end

    # Pattern exhausted - success, return end position
    ti
  end

  # Match a quantified atom (*, +, ?, {n,m})
  # Uses greedy/lazy matching with backtracking
  # quant_min: minimum repetitions required
  # quant_max: maximum repetitions allowed (-1 = unlimited)
  # lazy: if true, try shortest matches first (non-greedy)
  def match_quantified(pattern, atom_start, atom_end, quant_min, quant_max, lazy, rest_pi, text, ti, tlen)
    # Collect all possible match positions
    positions = []
    match_count = 0

    # Position with 0 matches
    if quant_min == 0
      positions << ti
    end

    # Match as many as possible (up to quant_max)
    current_ti = ti
    new_ti = match_atom(pattern, atom_start, text, current_ti, tlen)
    while new_ti
      match_count = match_count + 1
      # Only record positions at or above minimum
      if match_count >= quant_min
        positions << new_ti
      end
      # Stop if we've reached max (unless unlimited)
      if quant_max != -1 && match_count >= quant_max
        break
      end
      # Stop if no progress (empty match) - prevents infinite loop
      if new_ti == current_ti
        break
      end
      current_ti = new_ti
      new_ti = match_atom(pattern, atom_start, text, current_ti, tlen)
    end

    # If we couldn't reach minimum, fail
    if match_count < quant_min
      return nil
    end

    # Try positions - greedy tries longest first, lazy tries shortest first
    if lazy
      # Lazy: try shortest matches first (forward order)
      i = 0
      while i < positions.length
        pos = positions[i]
        result = match_from(pattern, rest_pi, text, pos, tlen)
        return result if result
        i = i + 1
      end
    else
      # Greedy: try longest matches first (reverse order)
      i = positions.length - 1
      while i >= 0
        pos = positions[i]
        result = match_from(pattern, rest_pi, text, pos, tlen)
        return result if result
        i = i - 1
      end
    end
    nil
  end

  # Match a single atom at position ti
  # Returns new text position or nil
  def match_atom(pattern, pi, text, ti, tlen)
    pc = pattern[pi]

    # Handle escape sequences
    if pc == 92  # '\'
      pi += 1
      ec = pattern[pi]  # escaped char
      return nil if ti >= tlen

      # Handle special escapes
      if ec == 100  # 'd' - digit
        return nil unless char_digit?(text[ti])
      elsif ec == 68  # 'D' - non-digit
        return nil if char_digit?(text[ti])
      elsif ec == 119  # 'w' - word char
        return nil unless char_word?(text[ti])
      elsif ec == 87  # 'W' - non-word char
        return nil if char_word?(text[ti])
      elsif ec == 115  # 's' - whitespace
        return nil unless char_space?(text[ti])
      elsif ec == 83  # 'S' - non-whitespace
        return nil if char_space?(text[ti])
      elsif ec >= 49 && ec <= 57  # '1'-'9' - backreference
        group_idx = ec - 48
        if @match_captures && group_idx <= @match_captures.length
          captured = @match_captures[group_idx - 1]
          if captured
            cap_len = captured.length
            ci = 0
            while ci < cap_len
              return nil if ti >= tlen
              return nil if text[ti] != captured[ci]
              ti = ti + 1
              ci = ci + 1
            end
            return ti
          end
        end
        return nil
      else
        # Escaped character - match literally
        return nil if text[ti] != ec
      end
      return ti + 1

    # Handle '[' - character class
    elsif pc == 91  # '['
      return nil if ti >= tlen
      pi += 1
      # Check for negation
      negated = false
      if pattern[pi] == 94  # '^'
        negated = true
        pi += 1
      end
      # Check if char matches class
      matched = false
      tc = text[ti]
      while pattern[pi] != 93  # ']'
        cc = pattern[pi]
        # Check for range a-z
        if pattern[pi + 1] == 45 && pattern[pi + 2] != 93  # '-' not followed by ']'
          range_end = pattern[pi + 2]
          if tc >= cc && tc <= range_end
            matched = true
          end
          pi += 3
        else
          # Single character
          if tc == cc
            matched = true
          end
          pi += 1
        end
      end
      # Apply negation
      matched = !matched if negated
      return nil unless matched
      return ti + 1

    # Handle '(' - group
    elsif pc == 40  # '('
      # Check if this is a capturing group or non-capturing (?:...)
      is_capturing = true
      group_start = pi + 1
      # Check for special group markers like (?:, (?=, (?<name>, etc.
      if group_start < pattern.length && pattern[group_start] == 63  # '?'
        group_start += 1
        if group_start < pattern.length
          type_char = pattern[group_start]
          if type_char == 58  # ':' - non-capturing (?:...)
            is_capturing = false
            group_start += 1
          elsif type_char == 60  # '<' - named capture (?<name>...)
            # Named capture IS capturing - skip to after the '>'
            is_capturing = true
            group_start += 1
            while group_start < pattern.length && pattern[group_start] != 62  # '>'
              group_start += 1
            end
            group_start += 1 if group_start < pattern.length  # skip '>'
          else
            # Other special groups (lookahead, etc.) - non-capturing
            is_capturing = false
            group_start += 1
          end
        end
      end

      # Assign capture index if this is a capturing group
      capture_index = nil
      if is_capturing && @match_captures
        capture_index = @next_capture_index
        @next_capture_index = @next_capture_index + 1
      end

      # Find matching ')' to get group end
      depth = 1
      group_end = group_start
      while group_end < pattern.length && depth > 0
        c = pattern[group_end]
        if c == 92  # '\' - skip escaped char
          group_end += 1
        elsif c == 40  # '('
          depth = depth + 1
        elsif c == 41  # ')'
          depth = depth - 1
          break if depth == 0
        end
        group_end += 1
      end
      # Extract group content manually (String#[start,len] not supported)
      group_content = ""
      gi = group_start
      while gi < group_end
        group_content << pattern[gi]
        gi = gi + 1
      end

      # Record start position for capture
      capture_start = ti

      # Match the group content as a sub-pattern
      result = match_from(group_content, 0, text, ti, tlen)

      # If matched and this is a capturing group, store the capture
      if result && capture_index
        # Build captured text manually
        captured = ""
        ci = capture_start
        while ci < result
          captured << text[ci]
          ci = ci + 1
        end
        @match_captures[capture_index] = captured
      end

      return result  # Returns new position or nil

    # Handle '.' - any character except newline (unless MULTILINE mode)
    elsif pc == 46  # '.'
      return nil if ti >= tlen
      # In multiline mode (/m), '.' matches newlines too
      multiline = (options & MULTILINE) != 0
      return nil if !multiline && text[ti] == 10  # newline
      return ti + 1
    else
      # Literal character
      return nil if ti >= tlen
      return nil if text[ti] != pc
      return ti + 1
    end
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

  # Helper: POSIX class match by first char of name
  # n0 is first char of class name: a=alnum, d=digit, s=space, u=upper, l=lower, w=word,
  # b=blank, c=cntrl, g=graph, x=xdigit, p=punct, P=print, A=ascii
  def __posix?(n0, c)
    if n0 == 97 then char_word?(c) && c != 95      # alnum
    elsif n0 == 100 then char_digit?(c)            # digit
    elsif n0 == 115 then char_space?(c)            # space
    elsif n0 == 117 then c >= 65 && c <= 90        # upper
    elsif n0 == 108 then c >= 97 && c <= 122       # lower
    elsif n0 == 119 then char_word?(c)             # word
    elsif n0 == 98 then c == 32 || c == 9          # blank
    elsif n0 == 99 then c < 32 || c == 127         # cntrl
    elsif n0 == 103 then c >= 33 && c <= 126       # graph
    elsif n0 == 120 then char_digit?(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)  # xdigit
    elsif n0 == 112 then (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)  # punct
    elsif n0 == 80 then c >= 32 && c <= 126        # print (P=80)
    elsif n0 == 65 then c >= 0 && c <= 127         # ascii (A=65)
    else false
    end
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
