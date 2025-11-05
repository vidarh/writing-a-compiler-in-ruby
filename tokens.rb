
require 'operators'
require 'set'

module Tokens

  Keywords = Set[
    :begin, :break, :case, :class, :def, :do, :else, :end, :ensure, :if,
    :module, :require, :require_relative, :rescue, :then, :unless, :when, :elsif,
    :protected, :next, :lambda, :stabby_lambda, :while, :until, :for, :in
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
    def self.expect(s, allow_negative = true)
      tmp = ""
      # Only consume leading '-' if allowed (i.e., after an operator, not after ')')
      tmp << s.get if allow_negative && s.peek == ?-
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
    def self.expect(s, allow_negative = true)
      i = Int.expect(s, allow_negative)
      return nil if i.nil?

      # IMPORTANT: Check for float/rational literals FIRST before converting
      # large integers to heap integers. If we have "4294967295.0", we want
      # to handle it as a Float, not try to convert 4294967295 to heap integer
      # and then fail when trying to append ".0" to the AST node.

      # Check for float FIRST
      if s.peek == ?.
        s.get  # consume '.'
        if !(?0..?9).member?(s.peek)
          s.unget(".")
          # Not a float, fall through to check for large integer
        else
          # It's a float - parse fractional part and return Float
          # Fractional part is never negative
          f = Int.expect(s, false)
          # Convert to string and let MRI parse as float
          # This works for any size number since MRI handles it
          num = "#{i}.#{f}"

          # Check for scientific notation exponent: e+19, e-10, E5, etc.
          if s.peek == ?e || s.peek == ?E
            s.get  # consume 'e' or 'E'
            num << "e"

            # Optional sign
            if s.peek == ?+ || s.peek == ?-
              num << s.get
            end

            # Exponent digits
            exp = Int.expect(s, false)
            if exp
              num << exp.to_s
            end
          end

          return num.to_f
        end
      end

      # Check for Rational literal: <number>r or <number>/<number>r
      if s.peek == ?r
        # Simple rational: 5r = Rational(5, 1)
        s.get  # consume 'r'
        return [:call, :Rational, [i, 1]]
      elsif s.peek == ?/
        # Could be rational literal: 6/5r
        s.get  # consume '/'

        # Try to parse denominator (never negative in rational literals)
        denom = Int.expect(s, false)
        if denom && s.peek == ?r
          # It's a rational literal!
          s.get  # consume 'r'
          return [:call, :Rational, [i, denom]]
        else
          # Not a rational literal, unget and continue
          if denom
            denom_str = denom.to_s
            s.unget(denom_str)
          end
          s.unget("/")
          # Fall through to check for large integer
        end
      end

      # Now check if integer exceeds fixnum range (-2^30 to 2^30-1)
      # If so, create a heap integer via Integer.__from_literal
      # IMPORTANT: Use fixnum arithmetic to avoid bootstrap issues
      # (literals that exceed fixnum range would trigger this very code!)
      half_max = 536870911  # 2^29 - 1 (fits in fixnum)
      max_fixnum = half_max * 2 + 1  # 2^30 - 1
      min_fixnum = -max_fixnum - 1   # -2^30

      if i > max_fixnum || i < min_fixnum
        # Extract sign and magnitude
        sign = i < 0 ? -1 : 1
        magnitude = i.abs

        # Split into 30-bit limbs (least significant first)
        # Compute limb_base as 2^30 using fixnum arithmetic
        # Use 2^29 * 2 to avoid exceeding fixnum range
        limb_base = 536870912 * 2  # (2^29) * 2 = 2^30
        limbs = []
        while magnitude > 0
          limbs << (magnitude % limb_base)
          magnitude = magnitude / limb_base
        end
        limbs << 0 if limbs.empty?

        # Generate AST: Integer.__from_literal([limbs...], sign)
        # This is a class method call on Integer
        return [:callm, :Integer, :__from_literal, [[:array, *limbs], sign]]
      end

      # Regular fixnum - return as-is
      return i
    end
  end
end

module Tokens
  class Tokenizer
    attr_accessor :keywords
    attr_reader :newline_before_current

    def scanner
      @s
    end

    def initialize(scanner,parser)
      @s = scanner
      @parser = parser
      @keywords = Keywords.dup
      @first = true
      @lastop = false
      @newline_before_current = false
    end

    def each
      @first = true
      # Reset @lastop to allow consuming leading whitespace/newlines in new parse
      @lastop = true
      while t = get and t[0]
        # FIXME: Fails without parentheses
        yield(*t)
        @first = false
      end
    end

    def unget(token)
      # a bit of a hack. Breaks down if we ever unget more than one token from the tokenizer.
      # token is an array [text, operator, type], so use token[0] not token.to_s
      token_text = token.is_a?(Array) ? token[0].to_s : token.to_s
      s = Scanner::ScannerString.new(token_text)
      # Always attach position - this ensures consistent behavior
      s.position = @lastpos
      @s.unget(s)
    end

    def get_quoted_exp(unget = false)
      @s.unget("%") if unget
      @s.expect(Quoted) { @parser.parse_defexp } #, nil]
    end

    def get_raw(prev_lastop = false)
      # FIXME: Workaround for a bug where "first" is not
      # identified as a variable if first introduced inside
      # the case block. Placing this here until the bug
      # is fixed.
      first = nil

      case @s.peek
      when ?",?'
        return [get_quoted_exp, nil]
      when DIGITS
        return [Number.expect(@s, prev_lastop), nil]
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
      when ?%
        # Handle percent literals or modulo operator
        # Context check: @first || prev_lastop means we're after an operator or at statement start
        # In that context, % starts a percent literal; otherwise it's modulo
        # Note: %s(...) for s-expressions is handled by SEXParser before tokenization
        if @first || prev_lastop
          @s.get  # consume '%'

          # Check for type character
          type = nil
          if @s.peek && ALPHA.member?(@s.peek)
            type = @s.get
          end

          # Check if we have a delimiter
          delim = @s.peek
          if delim && (delim == ?{ || delim == ?( || delim == ?[ || delim == ?< || delim == ?| || delim == ?! || delim == ?/)
            # Determine closing delimiter
            closing = case delim
            when ?{ then ?}
            when ?( then ?)
            when ?[ then ?]
            when ?< then ?>
            else delim
            end

            @s.get  # consume opening delimiter

            # Parse content until closing delimiter
            content = ""
            depth = 1
            paired = (delim == ?{ || delim == ?( || delim == ?[ || delim == ?<)

            while depth > 0
              c = @s.peek
              raise "Unterminated percent literal" if c == nil

              @s.get

              if paired && c == delim
                depth += 1
                content << c.chr
              elsif c == closing
                depth -= 1
                content << c.chr if depth > 0
              elsif c == ?\
                # Escape sequence
                content << c.chr
                next_c = @s.get
                content << next_c.chr if next_c
              else
                content << c.chr
              end
            end

            # Return based on type
            case type
            when ?Q, nil
              # %Q{} or %{} - double-quoted string
              return [content, nil]
            when ?q
              # %q{} - single-quoted string
              return [content, nil]
            when ?w
              # %w{} - array of words
              return [[:array, *content.split], nil]
            when ?i
              # %i{} - array of symbols
              # Must prefix with : so transform.rb recognizes them as symbols
              symbols = content.split.map { |word| (":#{word}").to_sym }
              return [[:array, *symbols], nil]
            else
              # Unknown type - treat as modulo
              @s.unget(type.chr) if type
              @s.unget("%")
            end
          else
            # No delimiter - treat as modulo
            @s.unget(type.chr) if type
            @s.unget("%")
          end
        end

        # Modulo operator
        @s.get
        return ["%", Operators["%"]]
      when ?/
        if @first || prev_lastop
          # Parse regexp literal
          @s.get  # consume '/'
          pattern = ""
          while true
            c = @s.get
            if c == ?/
              # End of regexp, skip modifiers for now
              while @s.peek && (@s.peek == ?i || @s.peek == ?m || @s.peek == ?x || @s.peek == ?o)
                @s.get
              end
              return [[:callm, :Regexp, :new, pattern], nil]
            elsif c == ?\
              # Escape sequence
              pattern << c.chr
              next_c = @s.get
              pattern << next_c.chr if next_c
            elsif c == nil
              raise "Unterminated regexp"
            else
              pattern << c.chr
            end
          end
        else
          # Division operator
          @s.get
          return ["/", Operators["/"]]
        end
      when ?-
        @s.get
        # Only parse as negative number if last token was an operator (not after ')' etc.)
        # Special case: Don't create negative literal if followed by ** to fix precedence
        # e.g., -2**12 should parse as -(2**12) not (-2)**12
        if prev_lastop && DIGITS.member?(@s.peek)
          # Look ahead: consume the number and check what follows
          num_str = ""
          while DIGITS.member?(@s.peek)
            num_str << @s.get
          end
          # Skip whitespace and check for **
          @s.nolfws
          followed_by_power = (@s.peek == ?* && (@s.get; @s.peek == ?*))

          # Only create negative literal if NOT followed by **
          if !followed_by_power
            # Unget the number and use Number.expect to properly handle large integers
            @s.unget(num_str)
            @s.unget("-")
            return [Number.expect(@s, true), nil]
          end

          # Followed by **, so unget the number and first * (second * is still in scanner)
          # Then return "-" operator by falling through
          @s.unget("*")
          @s.unget(num_str)
          # Fall through to return "-" operator (already consumed at line 404)
        end
        @lastop = true
        if @s.peek == ?>
          @s.get
          return [:stabby_lambda, nil, :atom]
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

          # Check for heredoc: << or <<- or <<~
          # Only treat as heredoc if previous token was an operator (like =, ,, etc.)
          if buf == "<<" && (@first || prev_lastop)
            # Peek ahead to see if this is a heredoc
            squiggly = false
            dash = false
            if @s.peek == ?~
              squiggly = true
              @s.get
            elsif @s.peek == ?-
              dash = true
              @s.get
            end

            # Check if next character starts an identifier or quoted heredoc marker
            if @s.peek && (ALPHA.member?(@s.peek) || @s.peek == ?_ || @s.peek == ?' || @s.peek == ?")
              # This is a heredoc!
              # Read the heredoc marker
              marker = ""
              quoted = false
              quote_char = nil

              if @s.peek == ?' || @s.peek == ?"
                quote_char = @s.get
                quoted = true
                while @s.peek && @s.peek != quote_char
                  marker << @s.get.chr
                end
                @s.get if @s.peek == quote_char  # consume closing quote
              else
                # Unquoted identifier
                while @s.peek && (ALPHA.member?(@s.peek) || DIGITS.member?(@s.peek) || @s.peek == ?_)
                  marker << @s.get.chr
                end
              end

              # Now read until end of line (there might be more code on this line)
              while @s.peek && @s.peek != ?\n
                @s.get
              end
              @s.get if @s.peek == ?\n  # consume newline

              # Read heredoc body until we find the marker
              body = ""
              while true
                line = ""
                while @s.peek && @s.peek != ?\n
                  line << @s.get.chr
                end

                # Check if this line is the closing marker
                if line.strip == marker
                  # DON'T consume trailing newline - leave it for normal statement boundary handling
                  # This ensures heredocs are treated identically to quoted strings
                  break
                end

                # Add this line to the body
                body << line
                if @s.peek == ?\n
                  body << "\n"
                  @s.get
                elsif @s.peek == nil
                  raise "Unterminated heredoc (expected #{marker})"
                end
              end

              # Process body based on heredoc type
              if squiggly
                # <<~ removes leading whitespace
                lines = body.split("\n", -1)
                # Find minimum indentation (ignoring empty lines)
                min_indent = nil
                i = 0
                while i < lines.length
                  l = lines[i]
                  if !l.strip.empty?
                    # Count leading whitespace
                    ws_count = 0
                    j = 0
                    while j < l.length && (l[j] == " " || l[j] == "\t")
                      ws_count += 1
                      j += 1
                    end
                    if min_indent == nil || ws_count < min_indent
                      min_indent = ws_count
                    end
                  end
                  i += 1
                end
                min_indent = 0 if min_indent == nil

                # Strip the minimum indentation from each line
                result_lines = []
                i = 0
                while i < lines.length
                  l = lines[i]
                  if l.strip.empty?
                    result_lines << l
                  else
                    # Remove min_indent characters from the start
                    if l.length > min_indent
                      result_lines << l[min_indent..-1]
                    else
                      result_lines << ""
                    end
                  end
                  i += 1
                end
                body = result_lines.join("\n")
              end

              # Return the heredoc body as a string token
              return [body, nil]
            else
              # Not a heredoc, put back the ~ or - if we consumed it
              @s.unget("~") if squiggly
              @s.unget("-") if dash
              # Fall through to normal << operator handling
            end
          end

          if third = @s.get
            buf2 = buf + third
            op = Operators[buf2]
            if op
              op_val = op.is_a?(Hash) ? op[:infix_or_postfix] : op
              @lastop = true if op_val && (op_val.type == :infix || op_val.type == :lp || op_val.type == :prefix)
              return [buf2, op]
            end
            @s.unget(third)
          end
          op = Operators[buf]
          if op
            op_val = op.is_a?(Hash) ? op[:infix_or_postfix] : op
            @lastop = true if op_val && (op_val.type == :infix || op_val.type == :lp || op_val.type == :prefix)
            return [buf, op]
          end
          @s.unget(second)
        end
        op = Operators[first]
        if op
          op_val = op.is_a?(Hash) ? op[:infix_or_postfix] : op
          @lastop = true if op_val && (op_val.type == :infix || op_val.type == :lp || op_val.type == :prefix)
          return [first, op]
        end
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
        if @lastop && @last && @last[0] != :return
          # Track if we're about to skip a newline with ws
          @newline_before_current = (@s.peek && @s.peek.ord == 10)
          @s.ws
        else
          @newline_before_current = false
          @s.nolfws
        end

        # Parser bug fix: Track newlines for @lastop to fix negative number parsing
        # This fixes: 4.ceildiv(-3) followed by -4.ceildiv(3) on next line
        # Without this, -4 is parsed as binary subtraction instead of unary minus
        # Store boolean directly to avoid local variable issues in self-hosted compiler
        @__at_newline = @s.peek ? (@s.peek.ord == 10) : false

        prev_lastop = @lastop
        @lastop = false
        @lastpos = @s.position
        res = get_raw(prev_lastop)
      end
      # The is_a? weeds out hashes, which we assume don't contain :rp operators
      # Save old @last to check what token preceded the newline
      old_last = @last
      @last = res
      # FIXME: res can be nil in some contexts, causing crashes later
      # Parser bug fix: Only set @lastop = true after newline if previous token was an operator
      # Stabby lambda method calls (-> { x }.a) should NOT skip newlines
      # But operators like ) should skip newlines to allow: 4.ceildiv(-3) \n -4.ceildiv(3)
      if @__at_newline && old_last && old_last[1] && old_last[1].is_a?(Oper)
        # Previous token was an operator, so newline can be skipped
        @lastop = true
      else
        # Normal logic: only set @lastop for non-rp operators
        @lastop = res && res[1] && (!res[1].is_a?(Oper) || res[1].type != :rp)
      end
      @curtoken = res
      return res
    end
  end
end
