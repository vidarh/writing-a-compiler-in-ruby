
require 'sym'

module Tokens
  class Atom
    def self.expect(s)
      tmp = ""   # accumulates identifier CONTENT only; positions come from the parser's s.position
      c = s.peek
      return Sym.expect(s) if c == ?: # This is a hack. Shoud be handled separately

      if c == ?@ || c == ?$
        tmp << s.get_ch
        tmp << s.get_ch if c == ?@ && s.peek == ?@
      end

      # c.ord >= 128 accepts UTF-8 multibyte bytes/chars in identifiers (e.g. Multibyteぁあ).
      if (c = s.peek) && (c == ?_ || Tokens.alpha?(c) || c.ord >= 128)
        tmp << s.get_ch

        while (c = s.peek) && (ALNUM.member?(c) || ?_ == c || c.ord >= 128)
          tmp << s.get_ch
        end
      elsif tmp == "$"
        # Handle special global variables
        # Single-character specials: $!, $@, $&, $`, $', $+, $,, $., $/, $:, $;, $<, $=, $>, $?, $\, and $~
        # Also $- followed by a single alphanumeric character (e.g., $-0, $-a, $-w)
        c = s.peek
        if c == ?-
          tmp << s.get_ch  # consume '-'
          # Check if there's an alphanumeric after the dash
          c = s.peek
          if c && (ALNUM.member?(c) || c == ?_)
            tmp << s.get_ch  # consume the character after the dash
          end
        elsif c && (c == ?! || c == ?@ || c == ?& || c == ?` || c == ?' || c == ?+ ||
                    c == ?, || c == ?. || c == ?/ || c == ?: || c == ?; || c == ?< ||
                    c == ?= || c == ?> || c == ?? || c == ?\\ || c == ?~)
          tmp << s.get_ch
        else
          # For other cases, consume one character
          tmp << s.get_ch
        end
        return tmp.to_sym
      end
      if tmp.size > 0 && (s.peek == ?! || s.peek == ??)
        tmp << s.get_ch
      end
      return nil if tmp == ""
      return tmp.to_sym
    end
  end
end
