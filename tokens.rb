
module Tokens

  class Atom
    def self.expect s
      tmp = ""
      if (c = s.peek) && ((?a .. ?z).member?(c) || (?A .. ?Z).member?(c))
        tmp += s.get
        
        while (c = s.peek) && ((?a .. ?z).member?(c) || 
                                  (?A .. ?Z).member?(c) || 
                                  (?0 .. ?9).member?(c) || ?_ == c)
          tmp += s.get
        end
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
      return nil if !s.expect('"')
      buf = ""
      while (e = escaped(s)); buf += e; end
      raise "Unterminated string" if !s.expect('"')
      return buf
    end
  end
end
