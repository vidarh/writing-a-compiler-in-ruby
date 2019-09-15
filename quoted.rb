
module Tokens
  class Quoted
    def self.escaped(s,q = '"'[0])
      return nil if s.peek == q
      e = s.get
      if e == 92.chr
        raised "Unexpected EOF" if !s.peek
        e = s.get
        case e
        when 'e'
          return 27.chr
        when 't'
          return 9.chr
        when 'n'
          return 10.chr
        else
          return e
        end
      end
      return e
    end

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
            s.expect("}")
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
      q = s.expect('"') || s.expect("'") || s.expect("%") or return nil

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
      elsif q == "%"
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
        when ?a .. ?z, ?A .. ?Z, ?0..?9
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
      r
    end
  end
end
