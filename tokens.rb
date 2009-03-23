
require 'operators'
require 'set'

module Tokens

  Keywords=Set[:def,:end,:if,:require,:include]

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
      while t = get and t[0]
        yield *t
      end
    end

    def get
      @s.nolfws
      case @s.peek
      when ?",?'
        return [@s.expect(Quoted),nil]
      when ?0 .. ?9
        return [@s.expect(Int),nil]
      when ?a .. ?z, ?A .. ?Z, ?@, ?$, ?:
        buf = @s.expect(Atom)
        if Keywords.member?(buf)
          @s.unget(buf.to_s)
          return [nil,nil]
        end
        return [buf,Operators[buf.to_s]] if Operators.member?(buf.to_s)
        return [buf,nil]
      when ?-
        @s.get
        if (?0 .. ?9).member?(@s.peek)
          @s.unget("-")
          return [@s.expect(Int),nil]
        end
        if @s.peek == ?=
          @s.get
          return ["-=",Operators["-="]]
        end
        return ["-",Operators["-"]]
      when nil
        return [nil,nil]
      else
        # Special cases - two character operators: 
        first = @s.get
        if second = @s.get
          buf = first + second
          if third = @s.get
            buf2 = buf + third
            op = Operators[buf2]
            return [buf2,op] if op
            @s.unget(third)
          end
          op = Operators[buf]
          return [buf,op] if op
          @s.unget(second)
        end
        op = Operators[first]
        return [first,op] if op
        @s.unget(first)
        return [nil,nil]
      end
    end
  end
end


