
require 'operators'
require 'set'

module Tokens

  Keywords=Set[:def,:end,:if,:return,:require,:include]

  class Atom
    def self.expect s
      tmp = ""
      c = s.peek
      if c == ?@ || c == ?$ || c == ?:
        tmp += s.get
        tmp == s.get if c == ?@ && s.peek == ?@
      end

      if (c = s.peek) && (c == ?_ || (?a .. ?z).member?(c) || (?A .. ?Z).member?(c))
        tmp += s.get
        
        while (c = s.peek) && ((?a .. ?z).member?(c) || 
                                  (?A .. ?Z).member?(c) || 
                                  (?0 .. ?9).member?(c) || ?_ == c)
          tmp += s.get
        end
      end
      if tmp.size > 0 && (s.peek == ?! || s.peek == ??)
        tmp += s.get
      end
      return nil if tmp == ""
      return tmp.to_sym
    end
  end

  class Int
    def self.expect s
      tmp = ""
      tmp += s.get if s.peek == ?-
      while (c = s.peek) && (?0 .. ?9).member?(c)
        tmp += s.get
      end
      return nil if tmp == ""
      tmp.to_i
    end
  end

  class Quoted
    def self.escaped(s)
      return nil if s.peek == ?"
      if s.expect("\\")
        raised "Unexpected EOF" if !s.peek
        return "\\"+s.get 
      end
      return s.get
    end


    def self.expect s
      q = s.expect('"') || s.expect("'") or return nil
      buf = ""
      if q == '"'
        while (e = escaped(s)); buf += e; end
        raise "Unterminated string" if !s.expect('"')
      else
        while (e = s.get) && e != "'"; buf += e; end
        raise "Unterminated string" if e != "'"
      end
      return buf
    end
  end

  class Tokenizer
    def initialize scanner
      @s = scanner
    end

    def each
      while t = get
        yield t
      end
    end

    def get
      @s.nolfws
      case @s.peek
      when ?",?'
        return @s.expect(Quoted)
      when ?0 .. ?9
        return @s.expect(Int)
      when ?a .. ?z , ?A .. ?Z, ?@, ?$, ?:
        buf = @s.expect(Atom)
        if Keywords.member?(buf)
          @s.unget(buf.to_s)
          return nil
        end
        return buf.to_s if AtomOperators.member?(buf.to_s)
        return buf
      when ?-
        @s.get
        if (?0 .. ?9).member?(@s.peek)
          @s.unget("-")
          return @s.expect(Int)
        end
        return "-"
      # Special cases - two character operators:
      when ?=, ?!, ?+, ?<
        first = @s.get
        second = @s.get
        buf = first + second
        op = Operators[buf]
        return buf if op
        @s.unget(second)
        return first
      when nil
        return nil
      else
        return @s.get if Operators[@s.peek.chr]
        return nil
      end
    end
  end
end


