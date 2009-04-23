
require 'operators'
require 'set'

module Tokens

  Keywords = Set[:def, :end, :if, :include, :begin, :rescue, :then,:else]

  class Sym
    def self.expect(s)
      return nil if s.peek != ?:
      s.get
      buf = Atom.expect(s)
      return ":#{buf.to_s}".to_sym if buf

      # Lots more operators are legal.
      # FIXME: Need to check which set is legal - it's annoying inconsistent it appears
      if s.peek == ?[
        s.get
        if s.peek == ?]
          s.get
          return :":[]=" if s.peek == ?=
          return :":[]"
        end
        s.unget("[")
      end 
      s.unget(":")
      return nil
   end
  end

  class Atom
    def self.expect(s)
      tmp = ""
      c = s.peek
      return Sym.expect(s) if c == ?: # This is a hack. Shoud be handled separately

      if c == ?@ || c == ?$
        tmp += s.get
        tmp += s.get if c == ?@ && s.peek == ?@
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
    def self.expect(s)
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


    def self.expect(s)
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
    attr_accessor :keywords

    def initialize(scanner)
      @s = scanner
      @keywords = Keywords.dup
      @lastop = false
    end

    def each
      while t = get and t[0]
        yield *t
      end
    end

    def unget(token)
      @s.unget(token)
    end

    def get_raw
      case @s.peek
      when ?",?'
        return [@s.expect(Quoted), nil]
      when ?0 .. ?9
        return [@s.expect(Int), nil]
      when ?a .. ?z, ?A .. ?Z, ?@, ?$, ?:, ?_
        buf = @s.expect(Atom)
        return [@s.get, Operators[":"]] if @s.peek == ?: and !buf
        if @keywords.member?(buf)
          @s.unget(buf.to_s)
          return [nil, nil]
        end
        return [buf, Operators[buf.to_s]] if Operators.member?(buf.to_s)
        return [buf, nil]
      when ?-
        @s.get
        if (?0 .. ?9).member?(@s.peek)
          @s.unget("-")
          return [@s.expect(Int), nil]
        end
        @lastop = true
        if @s.peek == ?=
          @s.get
          return ["-=",Operators["-="]]
        end
        return ["-",Operators["-"]]
      when nil
        return [nil, nil]
      else
        # Special cases - two/three character operators, and character constants
        first = @s.get
        if second = @s.get
          return [second[0], nil] if first == "?" and !([32, 10, 9, 13].member?(second[0])) #FIXME: Handle escaped characters, such as ?\s etc.

          buf = first + second
          if third = @s.get
            buf2 = buf + third
            op = Operators[buf2]
            return [buf2, op] if op
            @s.unget(third)
          end
          op = Operators[buf]
          return [buf, op] if op
          @s.unget(second)
        end
        op = Operators[first]
        return [first, op] if op
        @s.unget(first)
        return [nil, nil]
      end
    end

    def ws
      @s.ws
    end

    attr_reader :lasttoken

    def get
      @lasttoken = @curtoken
      @lastop ? @s.ws : @s.nolfws
      @lastop = false
      res = get_raw
      # The is_a? weeds out hashes, which we assume don't contain :rp operators
      @lastop = res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
      @curtoken = res
      return res
    end
  end
end


