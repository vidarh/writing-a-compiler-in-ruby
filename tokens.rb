
require 'operators'
require 'set'

module Tokens

  Keywords = Set[
    :begin, :break, :case, :class, :def, :do, :else, :end, :if, :include,
    :module, :require, :require_relative, :rescue, :then, :unless, :when, :elsif,
    :protected, :next
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
      c = s.peek
      if (c == nil) || (?0 .. ?9).member?(c) == false
        return nil
      end

      # Check for hex (0x) or binary (0b) prefix
      radix = 10
      if s.peek == ?0
        tmp << s.get
        c = s.peek
        if c == ?x || c == ?X
          # Hexadecimal
          radix = 16
          tmp << s.get
          while (c = s.peek) && ((c == ?_) || (?0 .. ?9).member?(c) || (?a .. ?f).member?(c) || (?A .. ?F).member?(c))
            tmp << s.get
          end
        elsif c == ?b || c == ?B
          # Binary
          radix = 2
          tmp << s.get
          while (c = s.peek) && ((c == ?_) || c == ?0 || c == ?1)
            tmp << s.get
          end
        else
          # Regular number starting with 0
          while (c = s.peek) && ((c == ?_) || (?0 .. ?9).member?(c))
            tmp << s.get
          end
        end
      else
        # Regular decimal number
        while (c = s.peek) && ((c == ?_) || (?0 .. ?9).member?(c))
          tmp << s.get
        end
      end
      return nil if tmp == ""

      # Parse the number based on radix
      num = 0
      i = 0
      len = tmp.length
      neg = false
      if tmp[0] == ?-
        neg = true
        i += 1
      end

      # Skip 0x or 0b prefix
      if radix == 16 && i < len && tmp[i] == ?0 && (tmp[i+1] == ?x || tmp[i+1] == ?X)
        i += 2
      elsif radix == 2 && i < len && tmp[i] == ?0 && (tmp[i+1] == ?b || tmp[i+1] == ?B)
        i += 2
      end

      # 29-bit limit (accounting for 1-bit tagging)
      # Stop parsing if number gets too big to prevent overflow
      max_safe = 134217728  # 2^27 - Stop before we overflow

      while i < len
        s = tmp[i]
        i = i + 1

        # Skip underscores in numbers (they're legal separators)
        if s == ?_
          # Continue to next iteration
        else
          digit_value = nil
          if radix == 10
            if (?0..?9).member?(s)
              digit_value = s.ord - ?0.ord
            else
              break
            end
          elsif radix == 16
            if (?0..?9).member?(s)
              digit_value = s.ord - ?0.ord
            elsif (?a..?f).member?(s)
              digit_value = s.ord - ?a.ord + 10
            elsif (?A..?F).member?(s)
              digit_value = s.ord - ?A.ord + 10
            else
              break
            end
          elsif radix == 2
            if s == ?0
              digit_value = 0
            elsif s == ?1
              digit_value = 1
            else
              break
            end
          end

          if digit_value
            # Stop if next digit would cause overflow
            break if num > max_safe
            num = num * radix + digit_value
          end
        end
      end
      if neg
        num = num * (-1)
      end
      return num
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
      @first = true
      @lastop = false
    end

    def each
      @first = true
      while t = get and t[0]
        # FIXME: Fails without parentheses
        yield(*t)
        @first = false
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
      #when ?/
      #  if @first || @lastop
      #    # FIXME: Parse regexp here?
      #    return [[:callm, :Regexp, :new, get_quoted_exp], nil]
      #  end
      #  return [@s.get, Operators["/"]]
      when ?-
        @s.get
        if DIGITS.member?(@s.peek)
          @s.unget("-")
          return [@s.expect(Number), nil]
        end
        @lastop = true
        if @s.peek == ?>
          @s.get
          return [:lambda, nil, :atom]
        end
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

              # Handle common escape sequences
              case third
              when "e"
                return [27, nil]  # ESC
              when "t"
                return [9, nil]   # TAB
              when "n"
                return [10, nil]  # LF
              when "r"
                return [13, nil]  # CR
              else
                # For other escapes, return the character itself
                return [third[0].chr.ord, nil]
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
      # FIXME: res can be nil in some contexts, causing crashes later
      @lastop = res && res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
      @curtoken = res
      return res
    end
  end
end
