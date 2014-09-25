
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
        tmp << s.get # FIXME: Need to check what characters are legal after $ (and not covered above)
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
