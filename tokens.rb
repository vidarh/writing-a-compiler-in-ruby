
require 'operators'
require 'set'

module Tokens

  Keywords = Set[
    :begin, :break, :case, :class, :def, :do, :else, :end, :if, :include,
    :module, :require, :rescue, :then, :unless, :when, :elsif, :lambda,
    :protected
  ]

  # Methods can end with one of these.
  # e.g.: empty?, flatten!, foo=
  MethodEndings = Set["?", "=", "!"]

  ALPHA_LOW  = ?a .. ?z
  ALPHA_HIGH = ?A .. ?Z
  DIGITS = ?0 .. ?9

  class CharSet
    def initialize *c
      @chars = Set[*c]
    end

    def << c
      @chars << c
    end

    def === other
      @chars.member?(other)
    end

    def member? other
      @chars.member?(other)
    end

    def to_a
      @chars.to_a
    end
  end

  ALPHA = CharSet.new(*ALPHA_LOW.to_a, *ALPHA_HIGH.to_a)
  ALNUM = CharSet.new(*ALPHA.to_a, *DIGITS.to_a)
end

require 'atom'
require 'sym'
require 'quoted'


module Tokens
  # Match a (optionally specific) keyword
  class Keyword
    def self.expect(s,match)
      a = Atom.expect(s)
      return a if (a == match)
      s.unget(a.to_s) if a
      return nil
    end
  end
end

module Tokens
  # A methodname can be an atom followed by one of the method endings
  # defined in MethodEndings (see top).
  class Methodname

    def self.expect(s)
      # FIXME: This is horribly inefficient.
      name = nil
      OPER_METHOD.each do |op|
        return name.to_sym if name = s.expect(op)
      end

      pre_name = s.expect(Atom)
      if pre_name
        suff_name = MethodEndings.select{ |me| s.expect(me) }.first

        pre_name = pre_name ? pre_name.to_s : nil
        suff_name = suff_name ? suff_name.to_s : nil
        # methodname is prefix + suffix
        return (pre_name.to_s + suff_name.to_s).to_sym
      end

      return nil
    end
  end
end

module Tokens
  class Int
    def self.expect(s)
      tmp = ""
      tmp << s.get if s.peek == ?-
      while (c = s.peek) && (?0 .. ?9).member?(c)
        tmp << s.get
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
end

module Tokens
  class Tokenizer
    attr_accessor :keywords

    def initialize(scanner,parser)
      @s = scanner
      @parser = parser
      @keywords = Keywords.dup
      @lastop = false

      # FIXME: Auto-nil instance variables that are not present in initialize
      @last = nil
    end

    def each
      while t = get and t[0]
        # FIXME: Fails without parentheses
        yield(*t)
      end
    end

    def unget(token)
      # a bit of a hack. Breaks down if we ever unget more than one token from the tokenizer.
      s = Scanner::ScannerString.new(token.to_s)
      s.position = @lastpos
      @s.unget(s)
    end

    def get_quoted_exp(unget = false)
      @s.unget("%") if unget
      @s.expect(Quoted) { @parser.parse_defexp } #, nil]
    end

    def get_raw
      # FIXME: Workaround for a bug where "first" is not 
      # identified as a variable if first introduced inside
      # the case block. Placing this here until the bug
      # is fixed.
      first = nil

      case @s.peek
      when ?",?'
        return [get_quoted_exp, nil]
      when DIGITS
        return [@s.expect(Number), nil]
      when ALPHA, ?@, ?$, ?:, ?_
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
        if DIGITS.member?(@s.peek)
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
          if first == "?" and !([32, 10, 9, 13].member?(second[0].chr.ord))
            # FIXME: This changed in Ruby 1.9 to return a string, which is just plain idiotic.
            if second == "\\"
              third = @s.get

              # FIXME: Handle the rest of the escapes
              if third == "n"
                return [10,nil]
              end
            else
              return [second[0].chr.ord,nil]
            end
          end

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

      if @last.is_a?(Array) && @last[1].is_a?(Oper) && @last[1].sym == :callm
        @lastop = false
        @lastpos = @s.position
        res = Methodname.expect(@s)
        res = [res,nil] if res
      else
        # FIXME: This rule should likely cover more
        # cases; may want additional flags
        if @lastop && @last[0] != :return
          @s.ws
        else
          @s.nolfws
        end

        @lastop = false
        @lastpos = @s.position
        res = get_raw
      end
      # The is_a? weeds out hashes, which we assume don't contain :rp operators
      @last = res
      @lastop = res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
      @curtoken = res
      return res
    end
  end
end


