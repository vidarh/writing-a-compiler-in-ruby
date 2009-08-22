
require 'operators'
require 'set'

module Tokens

  Keywords = Set[
    :begin, :case, :class, :def, :do, :else, :end, :if, :include,
    :module, :require, :rescue, :then, :unless, :when
  ]

  # Methods can end with one of these.
  # e.g.: empty?, flatten!, foo=
  MethodEndings = Set["?", "=", "!"]

  # Match a (optionally specific) keyword
  class Keyword
    def self.expect(s,match)
      a = Atom.expect(s)
      return a if (a == match)
      s.unget(a.to_s)
      return nil
    end
  end

  class Sym
    def self.expect(s)
      return nil if s.peek != ?:
      s.get
      buf = Atom.expect(s)
      bs = ":#{buf.to_s}"
      return bs.to_sym if buf
      c = s.peek
      buf = Quoted.expect(s)
      bs = ":#{buf.to_s}"
      return bs.to_sym if buf

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
      elsif s.peek == ?<
        s.get
        if s.peek == ?<
          s.get
          return :":<<"
        end
        s.unget("<")
        return :":<"
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
      elsif tmp == "$"
        tmp += s.get # FIXME: Need to check what characters are legal after $ (and not covered above)
        return tmp.to_sym
      end
      if tmp.size > 0 && (s.peek == ?! || s.peek == ??)
        tmp += s.get
      end
      return nil if tmp == ""
      return tmp.to_sym
    end
  end

  # A methodname can be an atom followed by one of the method endings
  # defined in MethodEndings (see top).
  class Methodname
    def self.expect(s)
      pre_name = s.expect(Atom)
      suff_name = MethodEndings.select{ |me| s.expect(me) }.first

      if pre_name || suff_name
        pre_name = pre_name ? pre_name.to_s : nil
        suff_name = suff_name ? suff_name.to_s : nil
        # methodname is prefix + suffix
        return (pre_name.to_s + suff_name.to_s).to_sym
      end

      return nil
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

  class Number
    def self.expect(s)
      i = Int.expect(s)
      return nil if i.nil?
      return i if s.peek != ?.
      s.get
      if !(?0..?9).member?(s.peek)
        s.unget(".")
        return i
      end
      f = Int.expect(s)
      # FIXME: Yeah, this is ugly. Do it nicer later.
      num = "#{i}.#{f}"
      num.to_f
    end
  end


  class Quoted
    def self.escaped(s,q = '"'.ord)
      return nil if s.peek == q
      if s.expect("\\")
        raised "Unexpected EOF" if !s.peek
        return "\\"+s.get
      end
      return s.get
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
            ret ||= [:concat]
            ret << buf 
            buf = ""
            s.get
            ret << yield
            s.expect("}")
          end
        else
          buf += e
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
        if e == '"'
          buf += "\\\""
        elsif e == "\\" && (s.peek == ?' || s.peek == "\\".ord)
          buf += "\\" + s.get
        else
          buf += e
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

      dquoted = true
      if q == "'"
        dquoted = false
      elsif q == "%"
        c = s.peek
        case c
        when ?q
          dquoted = false
        when ?Q
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

      return expect_dquoted(s,q,&block) if dquoted
      return expect_squoted(s,q)
    end
  end

  class Tokenizer
    attr_accessor :keywords

    def initialize(scanner,parser)
      @s = scanner
      @parser = parser
      @keywords = Keywords.dup
      @lastop = false
    end

    def each
      while t = get and t[0]
        yield *t
      end
    end

    def unget(token)
      # a bit of a hack. Breaks down if we ever unget more than one token from the tokenizer.
      s = Scanner::ScannerString.new(token.to_s)
      s.position = @lastpos
      @s.unget(s)
    end

    def get_raw
      case @s.peek
      when ?",?'
        return [@s.expect(Quoted) { @parser.parse_defexp }, nil]
      when ?0 .. ?9
        return [@s.expect(Number), nil]
      when ?a .. ?z, ?A .. ?Z, ?@, ?$, ?:, ?_
        if @s.peek == ?:
          @s.get
          if @s.peek == ?:
            @s.get
            return ["::", Operators["::"]]
          end
          @s.unget(":")
        end
        buf = @s.expect(Atom)
        return [@s.get, Operators[":"]] if !buf
        return [buf, Operators[buf.to_s]] if Operators.member?(buf.to_s)
        if @keywords.member?(buf)
          return [buf,nil, :keyword]
        end
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

        if @s.peek == ?%
          r = @s.expect(Quoted) { @parser.parse_defexp }
          return [r,nil] if r
        end

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
      @lastpos = @s.position
      res = get_raw
      # The is_a? weeds out hashes, which we assume don't contain :rp operators
      @lastop = res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
      @curtoken = res
      return res
    end
  end
end


