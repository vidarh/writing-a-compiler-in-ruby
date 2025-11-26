
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

    def self.escaped(s,q = DQ)
      return nil if s.peek == q
      e = s.get
      if e == CSI
        raised "Unexpected EOF" if !s.peek
        e = s.get
        case e
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
        else
          return e
        end
      end
      return e
    end

    HASH = "#"

    # Helper: Handle string interpolation #{...}
    # Returns true if interpolation was found and handled, false otherwise
    # If interpolation found, adds interpolated expression to ret array
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

    def self.expect_dquoted(s,q='"',&block)
      ret = nil
      buf = ""
      while (e = escaped(s,q[0]));
        if e == "#"
          # Check for interpolation #{...}
          result = handle_interpolation(s, ret, buf, &block)
          if result
            ret = result
            buf = ""
          # Check for simple interpolation #$var, #@ivar, #@@cvar
          elsif s.peek == ?$ || s.peek == ?@
            # Initialize ret as [:concat] if not already done
            ret = [:concat] if !ret
            ret << buf
            buf = ""

            # Parse the variable
            var_start = s.peek
            s.get  # consume $ or @

            # For class variables, consume second @
            if var_start == ?@ && s.peek == ?@
              s.get
              prefix = "@@"
            elsif var_start == ?@
              prefix = "@"
            else
              prefix = "$"
            end

            # Read variable name
            var_name = ""
            while s.peek && ((?a..?z).member?(s.peek) || (?A..?Z).member?(s.peek) ||
                            (?0..?9).member?(s.peek) || s.peek == ?_)
              var_name << s.get
            end

            # If no variable name found, treat as literal # followed by $ or @
            if var_name.empty?
              buf << "#" << var_start.chr
            else
              # Add the variable reference to interpolation
              ret << (prefix + var_name).to_sym
            end
          else
            buf << e
          end
        else
          buf << e
        end
      end
      raise "Unterminated string" if !s.expect(q)
      if ret
        ret << buf if buf != ""
        return ret
      else
        return buf
      end
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
