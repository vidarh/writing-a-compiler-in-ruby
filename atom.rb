
require 'sym'

module Tokens
  class Atom
    def self.expect(s)
      tmp = ""
      c = s.peek
      return Sym.expect(s) if c == ?: # This is a hack. Shoud be handled separately

      if c == ?@ || c == ?$
        tmp << s.get
        tmp << s.get if c == ?@ && s.peek == ?@
      end

      if (c = s.peek) && (c == ?_ || (?a .. ?z).member?(c) || (?A .. ?Z).member?(c))
        tmp << s.get

        while (c = s.peek) && (ALNUM.member?(c) || ?_ == c)
          tmp << s.get
        end
      elsif tmp == "$"
        # Handle special global variables
        # Single-character specials: $!, $@, $&, $`, $', $+, $,, $., $/, $:, $;, $<, $=, $>, $?, $\, and $~
        # Also $- followed by a single alphanumeric character (e.g., $-0, $-a, $-w)
        c = s.peek
        if c == ?-
          tmp << s.get  # consume '-'
          # Check if there's an alphanumeric after the dash
          c = s.peek
          if c && (ALNUM.member?(c) || c == ?_)
            tmp << s.get  # consume the character after the dash
          end
        elsif c && (c == ?! || c == ?@ || c == ?& || c == ?` || c == ?' || c == ?+ ||
                    c == ?, || c == ?. || c == ?/ || c == ?: || c == ?; || c == ?< ||
                    c == ?= || c == ?> || c == ?? || c == ?\\ || c == ?~)
          tmp << s.get
        else
          # For other cases, consume one character
          tmp << s.get
        end
        return tmp.to_sym
      end
      if tmp.size > 0 && (s.peek == ?! || s.peek == ??)
        tmp << s.get
      end
      return nil if tmp == ""
      return tmp.to_sym
    end
  end
end
