
require 'atom'
require 'quoted'

module Tokens

  class Sym
    def self.expect(s)
      return nil if s.peek != ?:
      s.get
      buf = Atom.expect(s)

      # If we got an atom (like 'a'), check if it's followed by '=' to form a setter symbol (like ':a=')
      # BUT: don't consume '=' if it's part of '=>' (hash rocket)
      if buf && s.peek == ?=
        s.get  # consume '='
        if s.peek == ?>
          # This is '=>' (hash rocket), not a setter symbol - unget the '='
          s.unget("=")
        else
          # This is a setter symbol like ':a='
          buf = "#{buf}=".to_sym
        end
      end

      bs = ":#{buf.to_s}"
      return bs.to_sym if buf

      # Check for operator symbols BEFORE Quoted.expect
      # because some operators (like %) can start string literals
      # Lots more operators are legal.
      # FIXME: Need to check which set is legal - it's annoying inconsistent it appears
      if s.peek == ?[
        s.get
        if s.peek == ?]
          s.get
          if s.peek == ?=
            s.get
            return :":[]="
          end
          return :":[]"
        end
        s.unget("[")
      elsif s.peek == ?/
        s.get
        return :":/"
      elsif s.peek == ?-
        s.get
        if s.peek == ?@
          s.get
          return :":-@"
        end
        return :":-"
      elsif s.peek == ?+
        s.get
        if s.peek == ?@
          s.get
          return :":+@"
        end
        return :":+"
      elsif s.peek == ?%
        s.get
        return :":%"
      elsif s.peek == ?*
        s.get
        if s.peek == ?*
          s.get
          return :":**"
        end
        return :":*"
      elsif s.peek == ?=
        s.get
        if s.peek == ?=
          s.get
          if s.peek == ?=
            s.get
            return :":==="
          end
          return :":=="
        elsif s.peek == ?~
          s.get
          return :":=~"
        end
        return :":="
      elsif s.peek == ?<
        s.get
        if s.peek == ?<
          s.get
          return :":<<"
        elsif s.peek == ?=
          s.get
          return :":<="
        end
        return :":<"
      elsif s.peek == ?>
        s.get
        if s.peek == ?>
          s.get
          return :":>>"
        elsif s.peek == ?=
          s.get
          return :":>="
        end
        return :":>"
      elsif s.peek == ?&
        s.get
        if s.peek == ?&
          # Don't consume second & - :&& is not a valid symbol, && is a keyword
          s.unget("&")
          return nil
        end
        return :":&"
      elsif s.peek == ?|
        s.get
        if s.peek == ?|
          # Don't consume second | - :|| is not a valid symbol, || is a keyword
          s.unget("|")
          return nil
        end
        return :":|"
      elsif s.peek == ?^
        s.get
        return :":^"
      elsif s.peek == ?~
        s.get
        return :":~"
      elsif s.peek == ?!
        s.get
        if s.peek == ?=
          s.get
          if s.peek == ?=
            s.get
            return :":!=="
          end
          return :":!="
        end
        return :":!"
      end

      c = s.peek
      buf = Quoted.expect(s)
      if buf
        # Handle empty string specially - need ":''".to_sym not ":".to_sym
        if buf == ""
          return ":''".to_sym
        end
        bs = ":#{buf.to_s}"
        return bs.to_sym
      end
      s.unget(":")
      return nil
   end
  end
end
