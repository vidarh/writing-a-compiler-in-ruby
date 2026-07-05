
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

  # Match regexp against string - returns position of match or nil.
  # Routes through #match so the $~ family is published.
  def =~(string)
    return nil if string.nil?
    m = match(string)
    m ? m.begin(0) : nil
  end

  # Publish the $~ family. $&/$`/$'/$1..$9 are PLAIN global slots in this
  # runtime (no frame-local semantics, no derived reads), so they are all
  # assigned at match time. match? paths deliberately skip this (MRI).
  def __set_last_match(m)
    $~ = m
    if m.nil?
      $& = nil
      $` = nil
      $' = nil
      $1 = nil
      $2 = nil
      $3 = nil
      $4 = nil
      $5 = nil
      $6 = nil
      $7 = nil
      $8 = nil
      $9 = nil
    else
      $& = m[0]
      $` = m.pre_match
      $' = m.post_match
      $1 = m[1]
      $2 = m[2]
      $3 = m[3]
      $4 = m[4]
      $5 = m[5]
      $6 = m[6]
      $7 = m[7]
      $8 = m[8]
      $9 = m[9]
    end
    m
  end

  # Match method - returns MatchData or nil
  def match(string, pos = 0)
    return nil if string.nil?
    text = string.to_s
    # Search from `pos` over the WHOLE text (no slicing) so positions come back absolute and \b sees the
    # character before pos.
    result = match_internal(text, pos)
    if result
      __set_last_match(MatchData.new(self, text, result[0], result[1], result[2], result[3], result[4]))
    else
      __set_last_match(nil)
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

  # Internal match - returns [start_pos, end_pos, captures] or nil. `start` is the (absolute) text position
  # to begin searching from; the whole text is passed so lookbehind-style checks (e.g. \b) see the real
  # preceding character rather than a sliced-off start.
  def match_internal(string, start = 0)
    return nil if string.nil?
    text = string.to_s
    tlen = text.length

    # Initialize capture tracking
    @match_captures = []
    @match_begins = []
    @match_ends = []
    @next_capture_index = 0
    @match_text = text  # Store text for capture extraction

    # Handle empty pattern
    return [start, start, [], [], []] if @source.length == 0

    # Check for start anchor
    anchored_start = (@source[0] == 94)  # '^'

    # If anchored at start, only try the start position
    if anchored_start
      end_pos = match_at(text, start, tlen)
      return end_pos ? [start, end_pos, @match_captures, @match_begins, @match_ends] : nil
    end

    # Try matching at each position from `start` onward
    i = start
    while i <= tlen
      # Reset captures for each starting position
      @match_captures = []
      @match_begins = []
      @match_ends = []
      @next_capture_index = 0
      end_pos = match_at(text, i, tlen)
      if end_pos
        return [i, end_pos, @match_captures, @match_begins, @match_ends]
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

  # Number of CAPTURING groups whose '(' occurs before `upto` in `pattern`. Used to give each simple group
  # a stable 0-based capture index derived from its position, so backtracking (which re-enters a group's
  # continuation) does not shift indices the way a mutating counter would. Non-capturing (?:, lookaround
  # (?= (?! (?<= (?<! are skipped; named (?<name> counts.
  def __count_cap(pattern, upto)
    n = 0
    i = 0
    plen = pattern.length
    while i < upto && i < plen
      c = pattern[i]
      if c == 92
        i = i + 2
      elsif c == 40  # '('
        if i + 1 < plen && pattern[i + 1] == 63  # '(?'
          if i + 2 < plen && pattern[i + 2] == 60 &&
             !(i + 3 < plen && (pattern[i + 3] == 61 || pattern[i + 3] == 33))
            n = n + 1   # (?<name> is capturing
          end
        else
          n = n + 1     # plain (
        end
        i = i + 1
      else
        i = i + 1
      end
    end
    n
  end

  # A "word" character for \b/\w purposes: [A-Za-z0-9_]. text[i] yields a character CODE here.
  def __word_char?(c)
    (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
  end

  # True when position ti sits on a word boundary: exactly one of the characters straddling it is a word
  # character (treating positions before the start / at the end as non-word).
  def __word_boundary?(text, ti, tlen)
    before = ti > 0 ? __word_char?(text[ti - 1]) : false
    after = ti < tlen ? __word_char?(text[ti]) : false
    before != after
  end

  # Core matching engine with backtracking support
  # Returns end text position if match succeeds, nil otherwise
  # `conts` is a stack of pending group continuations for backtracking INTO groups: each entry is
  # [outer_pattern, outer_pi, capture_index_or_nil, capture_start_ti]. When the current (sub)pattern is
  # exhausted, the nearest continuation is closed (recording its capture) and matching resumes in the outer
  # pattern -- so a greedy quantifier inside a group can still give characters back to a following atom.
  def match_from(pattern, pi, text, ti, tlen, conts = [], cap_base = 0)
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
        elsif c == 91 && in_class && scan_i + 1 < plen && pattern[scan_i + 1] == 58
          # POSIX class [:name:] inside a class: skip to its ']' so it doesn't end the class
          scan_i += 2
          scan_i += 1 while scan_i < plen && pattern[scan_i] != 93
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
          # Try this alternative (alternatives share the surrounding cap_base -- `a(b)|c(d)` gives both
          # groups index 1)
          result = match_from(alt, 0, text, ti, tlen, conts, cap_base)
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

      # Check for end anchor ('$'): zero-width, so it composes with continuations (it may not be the last
      # atom once groups resume the outer pattern).
      if pc == 36  # '$'
        return nil if ti != tlen
        pi += 1
        next
      end

      # Parse the current atom and check for quantifier
      atom_start = pi
      atom_end = nil
      # For a "simple" group -- plain (...) or non-capturing (?:...) -- we match its content with a
      # continuation so backtracking crosses the group boundary. Named/lookaround groups keep the atomic
      # match_atom path.
      simple_group = false
      simple_group_capturing = false
      simple_group_content = nil

      # Handle escape sequences
      if pc == 92  # '\'
        pi += 1
        return nil if pi >= plen  # Incomplete escape
        esc = pattern[pi]
        # \b (word boundary) and \B (non-boundary) are ZERO-WIDTH assertions: test the position, consume no
        # text, and carry on with the rest of the pattern at the same ti. (Previously \b was matched as an
        # ordinary escaped 'b'/blank, so /\bword\b/ never matched.)
        if esc == 98 || esc == 66
          at_b = __word_boundary?(text, ti, tlen)
          return nil if (esc == 98) != at_b
          pi += 1
          next
        end
        # \A / \z / \Z string anchors -- also zero-width. (\A/\Z were previously mis-handled as ordinary
        # escaped chars that consumed a character, so /\Ahello/ etc. never matched.) ti is an absolute
        # position, so \A matches only at 0, \z only at the very end, \Z at the end or just before a
        # trailing newline.
        if esc == 65        # \A - start of string
          return nil if ti != 0
          pi += 1
          next
        elsif esc == 122    # \z - end of string
          return nil if ti != tlen
          pi += 1
          next
        elsif esc == 90     # \Z - end of string, or immediately before a trailing "\n"
          return nil if !(ti == tlen || (ti == tlen - 1 && text[ti] == 10))
          pi += 1
          next
        end
        atom_end = pi + 1

      # Handle '[' - character class
      elsif pc == 91  # '['
        pi += 1
        pi += 1 if pi < plen && pattern[pi] == 94  # skip '^'
        # Find closing ']' -- a POSIX class [:name:] contains a ']' that must not close the class
        while pi < plen && pattern[pi] != 93
          if pattern[pi] == 91 && pi + 1 < plen && pattern[pi + 1] == 58  # '[:'
            pi += 2
            pi += 1 while pi < plen && pattern[pi] != 93
          end
          pi += 1
        end
        pi += 1 if pi < plen  # skip ']'
        atom_end = pi

      # Handle '(' - group
      elsif pc == 40  # '('
        # Simple groups go through the continuation path: plain '(...)' and named '(?<name>...)' / "(?'name'
        # ...)" are capturing; '(?:...)' is non-capturing. Lookaround ('(?=' '(?!' '(?<=' '(?<!') is left to
        # match_atom (zero-width). __count_cap counts plain and named groups, so positional capture indices
        # stay consistent.
        simple_group = true
        simple_group_capturing = true
        gstart = pi + 1
        if gstart < plen && pattern[gstart] == 63  # '?'
          c1 = gstart + 1 < plen ? pattern[gstart + 1] : 0
          c2 = gstart + 2 < plen ? pattern[gstart + 2] : 0
          if c1 == 58                                   # '(?:'
            simple_group_capturing = false
            gstart = gstart + 2
          elsif c1 == 60 && c2 != 61 && c2 != 33        # '(?<name>' (not '(?<=' / '(?<!')
            gstart = gstart + 2
            while gstart < plen && pattern[gstart] != 62  # '>'
              gstart = gstart + 1
            end
            gstart = gstart + 1 if gstart < plen        # skip '>'
          elsif c1 == 39                                # "(?'name'"
            gstart = gstart + 2
            while gstart < plen && pattern[gstart] != 39  # closing "'"
              gstart = gstart + 1
            end
            gstart = gstart + 1 if gstart < plen
          else
            simple_group = false                        # lookaround -> atomic path
          end
        end
        pi += 1
        # Skip special group markers like (?:, (?=, etc. (for the atomic-path atom_end)
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
        if simple_group
          # Extract the content between the (adjusted) start and the closing ')'
          gc = ""
          gi = gstart
          while gi < atom_end - 1
            gc << pattern[gi]
            gi = gi + 1
          end
          simple_group_content = gc
        end

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
        ti = match_quantified(pattern, atom_start, atom_end, quant_min, quant_max, quant_lazy, pi, text, ti, tlen, conts, cap_base)
        return ti  # Either nil (no match) or the final position (match)
      elsif simple_group
        # Non-quantified simple group: match its content with a continuation that resumes the outer
        # pattern (at `pi`, just after the group) and records the capture on the way out. This is what lets
        # a greedy quantifier inside the group backtrack across the group boundary. The capture index is
        # derived from the group's position (cap_base + capturing groups before it here), so re-entering the
        # group during backtracking does not shift it; the content sees a cap_base one past this group.
        inner_base = cap_base + __count_cap(pattern, atom_start)
        cap_idx = nil
        if simple_group_capturing && @match_captures
          cap_idx = inner_base
        end
        return match_from(simple_group_content, 0, text, ti, tlen,
                          conts + [[pattern, pi, cap_idx, ti, cap_base]], inner_base + 1)
      else
        # Match single atom
        ti = match_atom(pattern, atom_start, text, ti, tlen)
        return nil if ti.nil?
      end
    end

    # (Sub)pattern exhausted. Close the nearest pending group continuation (recording its capture) and
    # resume the outer pattern; if there are none, this branch matched.
    if conts.empty?
      return ti
    end
    cont = conts[-1]
    if cont[2]
      captured = ""
      cs = cont[3]
      while cs < ti
        captured << text[cs]
        cs = cs + 1
      end
      @match_captures[cont[2]] = captured
      # Record the group's begin/end char offsets (for MatchData#begin/#end/#offset).
      @match_begins[cont[2]] = cont[3]
      @match_ends[cont[2]] = ti
    end
    match_from(cont[0], cont[1], text, ti, tlen, conts[0...-1], cont[4])
  end

  # Match a quantified atom (*, +, ?, {n,m})
  # Uses greedy/lazy matching with backtracking
  # quant_min: minimum repetitions required
  # quant_max: maximum repetitions allowed (-1 = unlimited)
  # lazy: if true, try shortest matches first (non-greedy)
  def match_quantified(pattern, atom_start, atom_end, quant_min, quant_max, lazy, rest_pi, text, ti, tlen, conts = [], cap_base = 0)
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
        result = match_from(pattern, rest_pi, text, pos, tlen, conts, cap_base)
        return result if result
        i = i + 1
      end
    else
      # Greedy: try longest matches first (reverse order)
      i = positions.length - 1
      while i >= 0
        pos = positions[i]
        result = match_from(pattern, rest_pi, text, pos, tlen, conts, cap_base)
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
        # POSIX class [:name:] inside the class
        if cc == 91 && pattern[pi + 1] == 58  # '[:'
          n0 = pattern[pi + 2]
          n2 = pattern[pi + 4]
          pi += 2
          pi += 1 while pi < pattern.length && pattern[pi] != 93  # to the ']' of ':]'
          pi += 1
          matched = true if __posix?(n0, n2, tc)
        # Check for range a-z
        elsif pattern[pi + 1] == 45 && pattern[pi + 2] != 93  # '-' not followed by ']'
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

  # Helper: POSIX class match. Dispatch needs TWO chars of the name: n0 (first) alone is
  # ambiguous (alnum/alpha/ascii all start with 'a'; print/punct with 'p'), so n2 is the
  # name's THIRD char, which disambiguates every POSIX class.
  def __posix?(n0, n2, c)
    if n0 == 97                                     # a: alnum / alpha / ascii
      if n2 == 110 then char_word?(c) && c != 95    #   alnum
      elsif n2 == 112 then (c >= 65 && c <= 90) || (c >= 97 && c <= 122)  # alpha
      else c >= 0 && c <= 127                       #   ascii
      end
    elsif n0 == 100 then char_digit?(c)            # digit
    elsif n0 == 115 then char_space?(c)            # space
    elsif n0 == 117 then c >= 65 && c <= 90        # upper
    elsif n0 == 108 then c >= 97 && c <= 122       # lower
    elsif n0 == 119 then char_word?(c)             # word
    elsif n0 == 98 then c == 32 || c == 9          # blank
    elsif n0 == 99 then c < 32 || c == 127         # cntrl
    elsif n0 == 103 then c >= 33 && c <= 126       # graph
    elsif n0 == 120 then char_digit?(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)  # xdigit
    elsif n0 == 112                                 # p: print / punct
      if n2 == 105 then c >= 32 && c <= 126         #   print
      else (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)  # punct
      end
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

  def frozen?
    true
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

  # Map each named group in the source to the positional index/indices of the capturing group(s) with that
  # name: { "name" => [group_index, ...] }. Group indices count plain '(' and named '(?<n>' / "(?'n'"
  # left-to-right (non-capturing (?: and lookaround are skipped).
  def named_captures
    result = {}
    src = @source
    n = src.length
    i = 0
    group_idx = 0
    while i < n
      c = src[i]
      if c == 92          # backslash escape
        i = i + 2
      elsif c == 91       # '[' character class
        i = i + 1
        while i < n && src[i] != 93
          if src[i] == 92
            i = i + 3
          elsif src[i] == 91 && i + 1 < n && src[i + 1] == 58  # POSIX [:name:]
            i = i + 2
            i = i + 1 while i < n && src[i] != 93
            i = i + 1
          else
            i = i + 1
          end
        end
        i = i + 1
      elsif c == 40       # '('
        if i + 1 < n && src[i + 1] == 63   # '(?'
          c2 = i + 2 < n ? src[i + 2] : 0
          if (c2 == 60 && !(i + 3 < n && (src[i + 3] == 61 || src[i + 3] == 33))) || c2 == 39
            # named group (?<name> or (?'name'
            group_idx = group_idx + 1
            close = c2 == 60 ? 62 : 39   # '>' or "'"
            j = i + 3
            name = ""
            while j < n && src[j] != close
              name << src[j].chr
              j = j + 1
            end
            result[name] = [] if !result.has_key?(name)
            result[name] << group_idx
            i = j + 1
          else
            i = i + 1   # non-capturing / lookaround
          end
        else
          group_idx = group_idx + 1   # plain capturing group
          i = i + 1
        end
      else
        i = i + 1
      end
    end
    result
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
