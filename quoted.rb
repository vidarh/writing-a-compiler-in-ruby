
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

    def self.expect_dquoted(s,q='"')
      ret = nil
      buf = ""
      while (e = escaped(s,q[0])); 
        if e == "#" && s.peek == ?{
          # Uh-oh. String interpolation
          #
          # We'll need to do something dirty here:
          #
          # We will call back into the main parser... UGLY.
          # 
          # We need to do this because you need to do a full
          # parse to actually know when the string interpolation
          # ends, since it can be recursive (!)
          #
          # This has an ugly impact: We need to get the parser
          # object from somewhere. We'll pass that as a block.
          #
          # We will also need to return something other than a plain
          # string. We'll return [:concat, string, fragments, one, by, one]
          # where the fragments can be strings or expressions.
          # 
          # NOTE: There's a semi-obvious optimization here that is
          #  NOT universally safe: Any seeming constant expression
          #  could result in the concatenation done at compile time.
          #  For 99.99% of apps this would be safe, but in Ruby some
          #  moron *could* overload methods and make the seemingly
          #  constant expression have side effects. We'll likely have
          #  an option to do this optimization (with some safety checks,
          #  but for correctness we also need to be able to turn the
          #  :concat into [:callm, original-string, :concat] or similar.
          #
          if !block_given?
            STDERR.puts "WARNING: String interpolation requires passing block to Quoted.expect"
          else
            if !ret
              ret = [:concat]
            end
            #ret ||= [:concat]
            ret << buf 
            buf = ""
            s.get
            ret << yield
            s.expect_str("}")
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
