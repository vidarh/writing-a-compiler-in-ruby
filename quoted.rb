
module Tokens
  class Quoted
    CSI = 92.chr
    ESC = 27.chr
    TAB = 9.chr
    LF  = 10.chr

    PCT="%"
    LC=?a .. ?z
    UC=?A .. ?Z
    DIGITS=?0..?9

    DQ='#'[0]

    CR  = 13.chr

    def self.escaped(s,q = DQ, &term)
      if term
        return nil if term.call(s)
      else
        return nil if s.peek == q
      end
      e = s.get
      if e == CSI
        raised "Unexpected EOF" if !s.peek
        e = s.get
        case e
        when LF
          # Line continuation: \<newline> absorbs both characters
          return ""
        when 'r'
          return CR
        when 'e'
          return ESC
        when 't'
          return TAB
        when 'n'
          return LF
        when 'M'
          # Meta escape: \M-x or \M-\C-x or \M-\c-x
          if s.peek == ?-
            s.get  # consume the dash
            # Check if it's \M-\C- or \M-\c-
            if s.peek == CSI
              s.get  # consume backslash
              if s.peek == ?C || s.peek == ?c
                s.get  # consume C or c
                if s.peek == ?-
                  s.get  # consume dash
                  ch = s.get
                  # Meta-Control: set both bit 7 and apply control
                  return ((ch.ord & 0x1f) | 0x80).chr
                end
              end
            else
              # Just \M-x: set bit 7
              ch = s.get
              return (ch.ord | 0x80).chr
            end
          end
        when 'C', 'c'
          # Control escape: \C-x or \c-x
          if s.peek == ?-
            s.get  # consume the dash
            ch = s.get
            # Control: mask to lower 5 bits
            return (ch.ord & 0x1f).chr
          end
        when '#'
          # Escaped # - return special marker to prevent interpolation
          return :escaped_hash
        else
          return e
        end
      end
      return e
    end

    HASH = "#"

    # Helper: Handle string interpolation #{...}
    # Returns truthy (the updated ret array) if interpolation was found and handled, false otherwise.
    # If interpolation found, adds interpolated expression to ret array.
    def self.handle_interpolation(s, ret, buf, &block)
      if s.peek == ?{
        if !block_given?
          STDERR.puts "WARNING: String interpolation requires passing block to Quoted.expect"
          return false
        end

        # Initialize ret as [:concat] if not already done
        ret = [:concat] if !ret

        # Add any buffered string before the interpolation
        ret << buf

        # Consume the {
        s.get

        # Parse the interpolated expression
        ret << yield

        # Expect closing }
        s.expect_str("}")

        return ret
      end
      false
    end

    # Shared helper: Handle #$var, #@ivar, #@@cvar interpolation.
    # Called after a '#' is seen and handle_interpolation returned false.
    # If a variable is found, appends it to ret and returns the updated ret.
    # If no variable is found, appends to buf and returns nil.
    def self.handle_simple_interpolation(s, ret, buf)
      if s.peek == ?$ || s.peek == ?@
        ret = [:concat] if !ret
        ret << buf

        var_start = s.peek
        s.get  # consume $ or @

        second_at = false
        if var_start == ?@ && s.peek == ?@
          s.get
          prefix = "@@"
          second_at = true
        elsif var_start == ?@
          prefix = "@"
        else
          prefix = "$"
        end

        var_name = ""

        if prefix == "$" && s.peek
          next_char = s.peek
          if next_char == ?! || next_char == ?@ || next_char == ?$ || (?0..?9).member?(next_char)
            var_name << s.get
          else
            while s.peek && ((?a..?z).member?(s.peek) || (?A..?Z).member?(s.peek) ||
                            (?0..?9).member?(s.peek) || s.peek == ?_)
              var_name << s.get
            end
          end
        else
          while s.peek && ((?a..?z).member?(s.peek) || (?A..?Z).member?(s.peek) ||
                          (?0..?9).member?(s.peek) || s.peek == ?_)
            var_name << s.get
          end
        end

        if var_name.empty?
          # No variable name found — return chars to buf via caller
          # Return the characters that should be added to buf
          result = "#"
          result << var_start.chr
          result << "@" if second_at
          return result
        else
          ret << (prefix + var_name).to_sym
          return ret
        end
      end
      nil
    end

    # expect_dquoted reads a double-quoted string body from the scanner.
    # q: the closing quote character (e.g. '"')
    # term: optional termination proc - if provided, called instead of checking q.
    #   The proc receives the scanner and should return true when the string ends.
    #   When term is provided, q is ignored and the caller is responsible for
    #   consuming any terminator (the proc should NOT consume it).
    # block: passed through for #{} interpolation parsing
    def self.expect_dquoted(s, q='"', term=nil, &block)
      ret = nil
      buf = ""
      qchar = q ? q[0] : nil
      while (e = escaped(s, qchar, &term));
        if e == :escaped_hash
          buf << "#"
        elsif e == "#"
          result = handle_interpolation(s, ret, buf, &block)
          if result
            ret = result
            buf = ""
          else
            sresult = handle_simple_interpolation(s, ret, buf)
            if sresult.is_a?(String)
              buf << sresult
            elsif sresult
              ret = sresult
              buf = ""
            elsif s.peek != ?{
              buf << e
            end
          end
        else
          buf << e
        end
      end
      if !term
        raise "Unterminated string" if !s.expect(q)
      end
      if ret
        ret << buf if buf != ""
        return ret
      else
        return buf
      end
    end

    # Check if the scanner is positioned at a heredoc marker line.
    # Skips optional leading whitespace, then checks for the marker
    # followed by newline or EOF.
    # Returns truthy (the consumed text) if matched, nil otherwise.
    # Does NOT consume the trailing newline (it serves as statement separator).
    def self.heredoc_at_marker?(s, marker)
      consumed = ""

      # Skip leading whitespace
      while s.peek && (s.peek == " " || s.peek == "\t")
        consumed << s.get
      end

      # Check if marker follows
      i = 0
      while i < marker.length
        c = s.peek
        if c == nil || c != marker[i]
          s.unget(consumed) if !consumed.empty?
          return nil
        end
        consumed << s.get
        i += 1
      end

      # Marker must be followed by newline or EOF
      if s.peek == nil || s.peek == LF
        return consumed
      end

      s.unget(consumed) if !consumed.empty?
      return nil
    end

    # Scan ahead in the scanner to find the minimum indentation of the
    # heredoc body. Reads characters without processing escapes, tracking
    # indentation of non-blank lines. Ungets all characters read so the
    # scanner is left in its original state. Returns the min indent value.
    def self.heredoc_scan_indent(s, marker)
      consumed = ""
      min_indent = nil
      at_line_start = true
      current_indent = 0
      line_has_content = false

      while true
        c = s.peek
        break if c == nil

        if at_line_start
          # Check for marker (with optional leading whitespace)
          probe = ""
          while s.peek && (s.peek == " " || s.peek == "\t")
            probe << s.get
          end
          # Check if marker follows
          marker_match = true
          mi = 0
          while mi < marker.length
            mc = s.peek
            if mc == nil || mc != marker[mi]
              marker_match = false
              break
            end
            probe << s.get
            mi += 1
          end
          # Marker must be followed by newline or EOF
          if marker_match && (s.peek == nil || s.peek == LF)
            consumed << probe
            break
          end
          # Not marker — unget probe and continue reading line
          s.unget(probe) if !probe.empty?
          at_line_start = false
          current_indent = 0
          line_has_content = false
        end

        ch = s.get
        consumed << ch

        if ch == LF
          at_line_start = true
          if line_has_content
            if min_indent == nil || current_indent < min_indent
              min_indent = current_indent
            end
          end
        elsif at_line_start == false && !line_has_content && (ch == " " || ch == "\t")
          current_indent += 1
        elsif !line_has_content
          line_has_content = true
        end
      end

      # Unget everything so the scanner is back to the start of the body
      s.unget(consumed) if !consumed.empty?
      min_indent = 0 if min_indent == nil
      return min_indent
    end

    # expect_heredoc reads an interpolated heredoc body directly from the
    # scanner, reusing the shared escape (escaped) and interpolation
    # (handle_interpolation, handle_simple_interpolation) handling.
    # Terminates when the marker line is found. For squiggly heredocs,
    # strips min_indent whitespace from each source line before escape processing.
    def self.expect_heredoc(s, marker, squiggly, &block)
      # For squiggly heredocs, scan ahead to find min_indent, then strip
      # that many whitespace chars from each source line BEFORE escape
      # processing. This ensures line continuation (\<newline>) joins
      # correctly with the dedented content of the next source line.
      min_indent = 0
      if squiggly
        min_indent = heredoc_scan_indent(s, marker)
      end

      ret = nil
      buf = ""
      at_line_start = true
      strip_remaining = min_indent

      while true
        # At start of a source line, check for the closing marker
        if at_line_start
          if heredoc_at_marker?(s, marker)
            break
          end
          at_line_start = false
          strip_remaining = min_indent
        end

        # EOF check
        if s.peek == nil
          raise "Unterminated heredoc (expected #{marker.inspect})"
        end

        # Literal newline: append to buffer and mark next position as line start
        if s.peek == LF
          s.get
          buf << LF
          at_line_start = true
          next
        end

        # Strip leading whitespace for squiggly dedent (before escape processing)
        if strip_remaining > 0 && (s.peek == " " || s.peek == "\t")
          s.get
          strip_remaining -= 1
          next
        end
        strip_remaining = 0

        # Use shared escape handling; term block always returns false
        # because we handle termination above via heredoc_at_marker?
        e = escaped(s) { false }
        break if e == nil

        # Line continuation (\<newline>) consumed the newline inside escaped.
        # The scanner is now at the start of the next source line — strip indent.
        if e == "" && min_indent > 0
          strip_remaining = min_indent
          next
        end

        # Shared interpolation/char processing — same logic as expect_dquoted
        if e == :escaped_hash
          buf << "#"
        elsif e == "#"
          result = handle_interpolation(s, ret, buf, &block)
          if result
            ret = result
            buf = ""
          else
            sresult = handle_simple_interpolation(s, ret, buf)
            if sresult.is_a?(String)
              buf << sresult
            elsif sresult
              ret = sresult
              buf = ""
            elsif s.peek != ?{
              buf << e
            end
          end
        else
          buf << e
        end
      end

      # Finalize the result
      if ret
        ret << buf if buf != ""
        return ret
      else
        return buf
      end
    end

    # expect_heredoc_squoted reads a single-quoted heredoc body from the
    # scanner. No escape processing or interpolation — only \\ and \' are
    # handled (same as single-quoted strings). Reuses heredoc_at_marker?
    # and heredoc_scan_indent for termination and squiggly dedent.
    def self.expect_heredoc_squoted(s, marker, squiggly)
      min_indent = 0
      if squiggly
        min_indent = heredoc_scan_indent(s, marker)
      end

      buf = ""
      at_line_start = true
      strip_remaining = min_indent

      while true
        if at_line_start
          if heredoc_at_marker?(s, marker)
            break
          end
          at_line_start = false
          strip_remaining = min_indent
        end

        if s.peek == nil
          raise "Unterminated heredoc (expected #{marker.inspect})"
        end

        if s.peek == LF
          s.get
          buf << LF
          at_line_start = true
          next
        end

        # Strip leading whitespace for squiggly dedent
        if strip_remaining > 0 && (s.peek == " " || s.peek == "\t")
          s.get
          strip_remaining -= 1
          next
        end
        strip_remaining = 0

        e = s.get
        # Single-quoted: only \\ and \' are special
        if e == "\\" && (s.peek == "\\" || s.peek == ?')
          buf << "\\" + s.get
        else
          buf << e
        end
      end

      return buf
    end

    def self.expect_squoted(s,q = "'" )
      buf = ""
      while (e = s.get) && e != q
        if e == "\\" && (s.peek == ?' || s.peek == "\\"[0])
          buf << "\\" + s.get
        else
          buf << e
        end
      end
      raise "Unterminated string" if e != "'"
      return buf
    end

    def self.expect(s,&block)
      backtick = false
      q = s.expect('"') || s.expect("'") || s.expect("`") || s.expect("%") or return nil
      backtick = true if q == "`"

      # Handle "special" quoted syntaxes. Currently we only handle generalized quoted
      # strings, no backticks, regexps etc.. Examples:
      # %()        - double quote
      # %q/string/ - generalized single quote
      # %Q|String| - generalized double quote
      # (etc. - the opening/close characters can be more or less anything. If (,[,{
      #  the closing char is the counterpart - ),],}.)
      #
      # Note that we're explicitly *NOT* handling "%" followed by a whitespace character.
      # Not sure I ever want to, even though it's valid Ruby. Never seen it in the wild,
      # and it's horrendously evil: "1 % 2" is an expression. "% 2 " is the string "2".
      # "'1' + % 2 " is the string "12".
      #
      # For now we're doing % followed by a non-alphanumeric, non-whitespace
      # character.

      words   = false
      dquoted = true
      if q == "'"
        dquoted = false
      elsif q == PCT
        c = s.peek
        case c
        when ?q
          dquoted = false
          s.get
        when ?Q
          s.get
        when ?w
          words = true
          s.get
        when ?s
          # %s{} is a symbol literal, but %s() is hijacked for s-expressions
          # Only handle %s{} here
          s.get
          if s.peek == ?{
            # Symbol literal %s{...}
            s.get  # consume {
            buf = ""
            while s.peek && s.peek != ?}
              buf << s.get
            end
            s.get if s.peek == ?}  # consume }
            return ":#{buf}".to_sym
          else
            # It's %s() for s-expression, let caller handle it
            s.unget("s")
            s.unget("%")
            return nil
          end
        when LC,UC
          s.unget(c)
          return nil
        # FIXME: Separating this from above due to compiler bug
        when DIGITS
          s.unget(c)
          return nil
        end
        q = s.get
        if q == "(" then q = ")"
        elsif q == "{" then q = "}"
        elsif q == "[" then q = "]"
        end
      end

      r = dquoted ? expect_dquoted(s,q,&block) : expect_squoted(s,q)
      r = [:array].concat(r.split(" ")) if words
      # Convert backtick strings to system() calls
      r = [:call, :system, r] if backtick
      r
    end
  end
end
