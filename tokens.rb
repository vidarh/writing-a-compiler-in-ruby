
require 'operators'
require 'set'

module Tokens

  Keywords = Set[
    :begin, :break, :case, :class, :def, :do, :else, :end, :ensure, :if,
    :module, :require, :require_relative, :rescue, :then, :unless, :when, :elsif,
    :next, :stabby_lambda, :while, :until, :for, :in, :alias, :undef
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
      # A keyword is a bare word, never a symbol. Don't let Atom.expect consume a ":"-symbol here:
      # for e.g. :'' it returns :":" whose to_s is just ":", so the unget below would lose the quoted
      # part and corrupt the stream (leaving a bare ":" operator). Bail out before consuming.
      return nil if s.peek == ?:
      a = s.peek_atom
      return nil if a != match
      Atom.expect(s)
      return a
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
  # Allocation-free character-class tests. The old `(?0 .. ?9).member?(c)` idiom allocated a char Range
  # AND ran Enumerable#member? (which walks the range via String#succ, allocating a String per step) on
  # EVERY source character -- together the
  # single largest compile allocator (~10% of all allocations). `c.ord` is the byte value on both hosts
  # (String#ord / Integer#ord), so these behave identically MRI-hosted and self-hosted.
  def self.alpha?(c);    c && (b = c.ord) >= 65 && (b <= 90 || (b >= 97 && b <= 122)); end          # A-Za-z
  def self.digit?(c);    c && (b = c.ord) >= 48 && b <= 57; end                                   # 0-9
  def self.octdigit?(c); c && (b = c.ord) >= 48 && b <= 55; end                                   # 0-7
  def self.hexdigit?(c); c && (b = c.ord) >= 48 && (b <= 57 || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)); end  # 0-9A-Fa-f

  class Int
    def self.expect(s, allow_negative = true)
      tmp = ""
      # Only consume leading '-' if allowed (i.e., after an operator, not after ')')
      tmp << s.get_ch if allow_negative && s.peek == ?-
      c = s.peek
      if (c == nil) || Tokens.digit?(c) == false
        return nil
      end

      # Check for hex (0x) or binary (0b) prefix
      radix = 10
      if s.peek == ?0
        tmp << s.get_ch
        c = s.peek
        if c == ?x || c == ?X
          # Hexadecimal
          radix = 16
          tmp << s.get_ch
          while (c = s.peek) && ((c == ?_) || Tokens.hexdigit?(c))
            tmp << s.get_ch
          end
        elsif c == ?b || c == ?B
          # Binary
          radix = 2
          tmp << s.get_ch
          while (c = s.peek) && ((c == ?_) || c == ?0 || c == ?1)
            tmp << s.get_ch
          end
        elsif c == ?o || c == ?O
          # Octal with explicit prefix (0o17 / 0O17)
          radix = 8
          tmp << s.get_ch
          while (c = s.peek) && ((c == ?_) || Tokens.octdigit?(c))
            tmp << s.get_ch
          end
        else
          # Octal number starting with 0 (implicit, e.g. 017)
          radix = 8
          while (c = s.peek) && ((c == ?_) || Tokens.octdigit?(c))
            tmp << s.get_ch
          end
        end
      else
        # Regular decimal number
        while (c = s.peek) && ((c == ?_) || Tokens.digit?(c))
          tmp << s.get_ch
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
      elsif radix == 8 && i < len && tmp[i] == ?0 && (tmp[i+1] == ?o || tmp[i+1] == ?O)
        i += 2  # explicit 0o/0O prefix (implicit-octal 017 has no letter to skip)
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
            if Tokens.digit?(s)
              digit_value = s.ord - ?0.ord
            else
              break
            end
          elsif radix == 16
            if Tokens.digit?(s)
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
          elsif radix == 8
            if Tokens.octdigit?(s)
              digit_value = s.ord - ?0.ord
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
    # Read a run of decimal digits, allowing (and dropping) '_' separators that sit BETWEEN two digits
    # (Ruby's numeric underscores, e.g. 3.14159_26535). A '_' not followed by a digit is not a
    # separator, so it is put back and left in the stream. Used for a float's fractional and exponent
    # digits (Int.expect already handles underscores in the integer part).
    def self.read_digits(s)
      out = ""
      while true
        c = s.peek
        if Tokens.digit?(c)
          out << s.get_ch
        elsif c == ?_
          s.get
          if Tokens.digit?(s.peek)
            # separator between digits: dropped; the loop reads the following digit next
          else
            s.unget("_")
            break
          end
        else
          break
        end
      end
      out
    end

    # Is c a character that continues an identifier (so an `i` before it is NOT an imaginary suffix,
    # e.g. `5if` == `5 if`, `5in` == `5 in`)?
    def self.ident_char?(c)
      return false if c.nil?
      b = c.ord
      (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 95
    end

    # A trailing `i` immediately after a numeric literal is the imaginary suffix (5i, 3.2i, 0.0i ->
    # Complex(0, n)) -- but only if it does not run into an identifier. Consume and return true when it
    # is the suffix; otherwise leave the stream untouched.
    def self.imaginary_suffix?(s)
      return false unless s.peek == ?i
      s.get
      if ident_char?(s.peek)
        s.unget("i")
        false
      else
        true
      end
    end

    def self.expect(s, allow_negative = true)
      # Capture a leading '-' BEFORE Int.expect consumes it: for "-0.5" Int.expect parses the integer
      # part "-0" as the integer 0, discarding the sign, so the float string would wrongly become "0.5".
      neg = allow_negative && s.peek == ?-
      i = Int.expect(s, allow_negative)
      return nil if i.nil?

      # IMPORTANT: Check for float/rational literals FIRST before converting
      # large integers to heap integers. If we have "4294967295.0", we want
      # to handle it as a Float, not try to convert 4294967295 to heap integer
      # and then fail when trying to append ".0" to the AST node.

      # Check for float FIRST
      if s.peek == ?.
        s.get  # consume '.'
        if !Tokens.digit?(s.peek)
          s.unget(".")
          # Not a float, fall through to check for large integer
        else
          # It's a float - parse fractional part and return Float.
          # Read the fractional digits as a raw decimal string: integer-literal parsing
          # (Int.expect) would treat a leading zero as octal, but fractional digits are
          # plain decimal (e.g. .090 is ninety-thousandths, and 9 is not a valid octal digit).
          f = Number.read_digits(s)
          num = "#{i}.#{f}"
          # Restore the sign lost when Int.expect turned "-0" into 0 (e.g. -0.5, -0.0).
          num = "-#{num}" if neg && i == 0

          # Check for scientific notation exponent: e+19, e-10, E5, etc.
          if s.peek == ?e || s.peek == ?E
            s.get  # consume 'e' or 'E'
            num << "e"

            # Optional sign
            if s.peek == ?+ || s.peek == ?-
              num << s.get_ch
            end

            # Exponent digits: read as a raw decimal string, exactly like the fractional part
            # above. Int.expect would treat a leading zero as OCTAL, so "1.0e-08" parsed "0" as
            # octal, stopped at the invalid octal digit "8", and left "8" in the stream -> the
            # literal became "1.0e-0" followed by a stray integer 8, which then got mis-parsed as
            # a call `(1.0e-0)(8)` and SIGSEGV'd through the float's tagged bits. Exponents are
            # always decimal (e-08 == e-8), so read the digits directly (dropping '_' separators).
            num << Number.read_digits(s)
          end

          # Carry the literal as its DECIMAL STRING (not `num.to_f`): the assembler turns
          # `.double <string>` into IEEE bytes at assemble time, so no compile-time float math /
          # String#to_f is needed. This is what makes float literals compile SELF-HOSTED (the
          # compiler's own String#to_f is stubbed). See compile_float / FLOAT_SUPPORT_PLAN.md.
          return [:call, :Complex, [0, [:float, num]]] if Number.imaginary_suffix?(s)
          return [:float, num]
        end
      end

      # Exponent-only float with no decimal point (10e15, 1E-9, 2e5). The exponent is e/E followed by an
      # optional sign and at least one digit; only then is it a numeric suffix. Otherwise (e.g. `10end`)
      # the consumed characters are restored so the identifier tokenizes normally.
      if s.peek == ?e || s.peek == ?E
        e_char = s.get
        esign = ""
        if s.peek == ?+ || s.peek == ?-
          esign = s.get
        end
        if Tokens.digit?(s.peek)
          num = "#{i}e#{esign}#{Number.read_digits(s)}"
          num = "-#{num}" if neg && i == 0   # restore sign lost when Int.expect turned "-0" into 0
          return [:call, :Complex, [0, [:float, num]]] if Number.imaginary_suffix?(s)
          return [:float, num]
        else
          # Not an exponent -- put the consumed characters back (e/E first on re-read).
          s.unget(esign) if !esign.empty?
          s.unget(e_char)
        end
      end

      # Imaginary integer literal: 5i -> Complex(0, 5).
      return [:call, :Complex, [0, i]] if Number.imaginary_suffix?(s)

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
    attr_accessor :newline_before_current
    attr_reader :at_newline

    def scanner
      @s
    end

    def last_ws_consumed_newline
      @s.last_ws_consumed_newline
    end

    def initialize(scanner,parser)
      @s = scanner
      @parser = parser
      @keywords = Keywords.dup
      @first = true
      @lastop = false
      @newline_before_current = false
      @at_newline = false
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

    # Join two adjacent string-literal values. Two plain Strings concatenate at parse time (matching MRI's
    # single frozen literal); if either carries interpolation it is a [:concat, ...part] node, so merge the
    # parts into one [:concat, ...] that concatenates them at runtime.
    def concat_string_literals(a, b)
      return a + b if a.is_a?(String) && b.is_a?(String)
      aparts = (a.is_a?(Array) && a[0] == :concat) ? a[1..-1] : [a]
      bparts = (b.is_a?(Array) && b[0] == :concat) ? b[1..-1] : [b]
      [:concat, *aparts, *bparts]
    end

    # Consume a run of adjacent string literals and concatenate them onto `s` (Ruby joins `"a" "b"` =>
    # "ab", including across a backslash-continued line). Skip SAME-LINE whitespace between them (nolfws
    # joins a backslash+newline but stops at a real newline, so `"a"\n"b"` stays two statements) and, while
    # another string literal immediately follows, parse and join it. Without this the juxtaposed values
    # were parsed as a command call `"a"("b")` -- calling a String literal through its data -> SIGSEGV.
    def get_adjacent_strings(s)
      @s.nolfws
      # 34/39/96 = " ' ` -- the string-literal delimiters.
      while (nx = @s.peek) && (nx.ord == 34 || nx.ord == 39 || nx.ord == 96)
        s = concat_string_literals(s, get_quoted_exp)
        @s.nolfws
      end
      s
    end

    def get_raw(prev_lastop = false)
      # FIXME: Workaround for a bug where "first" is not
      # identified as a variable if first introduced inside
      # the case block. Placing this here until the bug
      # is fixed.
      first = nil

      # A leading UTF-8 multibyte byte (>= 128) starts an identifier (e.g. a variable named "ë").
      # The case below dispatches identifiers via ALPHA/_/@/$, none of which match a multibyte byte,
      # so handle it here as a plain name (Atom.expect already accepts >= 128 in identifiers).
      if (mb = @s.peek) && mb.ord >= 128
        buf = @s.expect(Atom)
        return [buf, nil] if buf
      end

      case @s.peek
      when ?`,?",?'
        # Adjacent string literals are concatenated (Ruby): `"foo" "bar" "baz"` => "foobarbaz". See
        # get_adjacent_strings; kept in its own method so its loop variable is a clean method local (a var
        # assigned only inside a case/when branch is not reliably registered by the self-hosted compiler).
        strlit = get_adjacent_strings(get_quoted_exp)
        # In a `# frozen_string_literal: true` file, a plain (non-interpolated) literal is frozen; freezing
        # it marks the node so rewrite_strconst emits the frozen form. Interpolated literals come back as a
        # [:concat,...] Array (not frozen in MRI either), so the is_a?(String) guard skips them.
        strlit.freeze if strlit.is_a?(String) && @parser && @parser.frozen_literals
        return [strlit, nil]
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
        # Don't check symbols (whose to_s starts with :) against operators
        # This prevents empty symbol :"" (which has to_s ":") from matching ternary operator
        s = buf.to_s
        # A keyword/operator name immediately followed by ':' is a label (e.g. in:, if:, class:),
        # not the keyword/operator -- fall through to a plain name so the parser builds a pair.
        unless @s.peek == ?:
          return [buf, Operators[s]] if s[0] != ?: && Operators.member?(s)
          if @keywords.member?(buf)
            return [buf,nil, :keyword]
          end
        end
        return [buf, nil]
      when ?%
        # Handle percent literals or modulo operator
        # Note: %s(...) for s-expressions is handled by SEXParser before tokenization
        #
        # Heuristic to distinguish percent literals from modulo:
        # 1. After an operator or at statement start: always percent literal
        # 2. Followed by letter + non-alnum (like %Q{): always percent literal
        # 3. Followed by non-alnum that's not space (like %{): percent literal if after operator/start
        # 4. Otherwise: modulo operator
        #
        # This handles both:
        # - Standard cases: x = %Q{...} (at statement start)
        # - Argument cases: eval %Q{...} (after identifier, but followed by Q{)

        # Separate handling for %Q and %{ specifically
        # These need to work even after an identifier (like `eval %{...}`)
        percent_start_pos = @s.position  # Save position before consuming
        pct_char = @s.get  # consume '%'

        # Check for %{ (plain percent literal with brace delimiter)
        if @s.peek == ?{
          delim = "{"
          closing = "}"
          @s.get  # consume opening delimiter

          # Parse content until closing delimiter, handling interpolation
          ret = nil
          buf = ""
          depth = 1

          while depth > 0
            c = @s.peek
            raise CompilerError.new("Unterminated percent literal", percent_start_pos) if c == nil

            @s.get
            if c == "\\"
              # Handle escape sequences
              next_char = @s.peek
              if next_char
                @s.get
                buf << "\\" << next_char
              else
                buf << "\\"
              end
            elsif c == "{"
              depth += 1
              buf << c
            elsif c == closing
              depth -= 1
              buf << c if depth > 0
            elsif c == "#"
              # Check for interpolation #{ (only if not the closing delimiter)
              if @s.peek == "{"
                # Use Quoted.handle_interpolation helper
                result = Tokens::Quoted.handle_interpolation(@s, ret, buf) { @parser.parse_defexp }
                if result
                  ret = result
                  buf = ""
                end
              else
                # Not interpolation, add literal "#" to buffer
                buf << "#"
              end
            else
              buf << c
            end
          end

          # Return interpolated string or plain string
          if ret
            ret << buf if buf != ""
            return [ret, nil]
          else
            return [buf, nil]
          end
        elsif @s.peek == ?Q
          type = @s.get  # consume 'Q'

          # Check if we have a delimiter
          delim = @s.peek
          is_delimiter = delim && !ALNUM.member?(delim)
          if is_delimiter
            # Determine closing delimiter
            closing = case delim
            when "{" then "}"
            when "(" then ")"
            when "[" then "]"
            when "<" then ">"
            else delim
            end

            @s.get  # consume opening delimiter

            # Parse content until closing delimiter, handling interpolation
            ret = nil
            buf = ""
            depth = 1
            paired = (delim == "{" || delim == "(" || delim == "[" || delim == "<")

            while depth > 0
              c = @s.peek
              raise CompilerError.new("Unterminated percent literal", percent_start_pos) if c == nil

              @s.get
              if c == "\\"
                # Handle escape sequences
                next_char = @s.peek
                if next_char
                  @s.get
                  buf << "\\" << next_char
                else
                  buf << "\\"
                end
              elsif paired && c == delim
                depth += 1
                buf << c
              elsif c == closing
                depth -= 1
                buf << c if depth > 0
              elsif c == "#"
                # Check for interpolation #{ (only if not the closing delimiter)
                if @s.peek == "{"
                  # Use Quoted.handle_interpolation helper
                  result = Tokens::Quoted.handle_interpolation(@s, ret, buf) { @parser.parse_defexp }
                  if result
                    ret = result
                    buf = ""
                  end
                else
                  # Not interpolation, add literal "#" to buffer
                  buf << "#"
                end
              else
                buf << c
              end
            end

            # Return interpolated string or plain string
            if ret
              ret << buf if buf != ""
              return [ret, nil]
            else
              return [buf, nil]
            end
          else
            # Not a valid delimiter - treat as modulo
            @s.unget  # put back Q
            @s.unget  # put back %
            return read_token  # retry
          end
        elsif @s.peek == ?s
          # %s{} is a symbol literal
          # Note: %s() is hijacked for s-expressions, so only handle %s{}
          @s.get  # consume 's'
          if @s.peek == ?{
            @s.get  # consume '{'
            buf = ""
            while @s.peek && @s.peek != ?}
              buf << @s.get
            end
            @s.get if @s.peek == ?}  # consume '}'
            return [":#{buf}".to_sym, nil]
          else
            # Not %s{} - unget and let other code handle it
            @s.unget  # put back s
            @s.unget  # put back %
            return read_token  # retry
          end
        elsif @first || prev_lastop
          # '%' already consumed above
          # percent_start_pos already set before consuming '%'

          # Check for type character
          type = nil
          if @s.peek && ALPHA.member?(@s.peek)
            type = @s.get
          end

          # Check if we have a delimiter
          # Percent literals can use any non-alphanumeric character as delimiter
          delim = @s.peek
          is_delimiter = delim && !ALNUM.member?(delim)
          if is_delimiter
            # Determine closing delimiter
            closing = case delim
            when "{" then "}"
            when "(" then ")"
            when "[" then "]"
            when "<" then ">"
            else delim
            end

            @s.get  # consume opening delimiter

            # Parse content until closing delimiter
            # For %Q, %W, %I, %x, %r: handle interpolation
            # For %q, %w, %i: no interpolation
            ret = nil
            buf = ""
            depth = 1
            paired = (delim == "{" || delim == "(" || delim == "[" || delim == "<")
            needs_interpolation = (type == ?Q || type == nil || type == ?W || type == ?I || type == ?x || type == ?r)

            while depth > 0
              c = @s.peek
              raise CompilerError.new("Unterminated percent literal", percent_start_pos) if c == nil

              @s.get

              if c.ord == 92 && delim != "\\"  # backslash (but not if backslash is the delimiter)
                # Escape sequence - consume next character literally
                buf << c.chr
                next_c = @s.get
                buf << next_c.chr if next_c
              elsif paired && c == delim
                depth += 1
                buf << c.chr
              elsif c == closing
                depth -= 1
                buf << c.chr if depth > 0
              elsif needs_interpolation && c == "#"
                # Check for interpolation #{ (only for types that support it, and only if not the delimiter)
                if @s.peek == "{"
                  # Use Quoted.handle_interpolation helper
                  result = Tokens::Quoted.handle_interpolation(@s, ret, buf) { @parser.parse_defexp }
                  if result
                    ret = result
                    buf = ""
                  end
                else
                  # Not interpolation, add literal "#" to buffer
                  buf << "#"
                end
              else
                buf << c.chr
              end
            end

            # Finalize content
            content = if ret
              ret << buf if buf != ""
              ret
            else
              buf
            end

            # Return based on type
            case type
            when ?Q, nil
              # %Q{} or %{} - double-quoted string (with interpolation)
              return [content, nil]
            when ?q
              # %q{} - single-quoted string
              return [content, nil]
            when ?w
              # %w{} - array of words (no interpolation)
              return [[:array, *content.split], nil]
            when ?W
              # %W{} - array of words (with interpolation)
              # content might be a string or [:concat, ...] array
              if content.is_a?(Array)
                # Interpolated - need to split at runtime
                # For now, just return the interpolated string wrapped in a split call
                # TODO: This is a simplification - proper implementation would split on whitespace
                return [[:call, content, :split], nil]
              else
                # No interpolation - split at compile time
                return [[:array, *content.split], nil]
              end
            when ?i, ?I
              # %i{} - array of symbols (no interpolation)
              # %I{} - array of symbols (with interpolation)
              # Must prefix with : so transform.rb recognizes them as symbols
              if content.is_a?(Array)
                # Interpolated - call helper to split and convert to symbols at runtime
                return [[:callm, content, :__percent_I], nil]
              else
                # No interpolation - split at compile time
                symbols = content.split.map { |word| (":#{word}").to_sym }
                return [[:array, *symbols], nil]
              end
            when ?x
              # %x{} - command execution (same as backticks)
              # For now, only support literal strings without interpolation
              # Build the AST node directly: [:call, :system, [string]]
              # TODO: Support interpolation like backticks do
              return [[:call, :system, [content]], nil]
            when ?r
              # %r{} - regexp literal
              # For now, convert to Regexp.new(string) call without interpolation or modifiers
              # TODO: Support interpolation and modifiers (i, m, x, o)
              return [[:callm, :Regexp, :new, content], nil]
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
        else
          # Not %Q and not (@first || prev_lastop) - treat as modulo
          # '%' already consumed above, so don't consume again
        end

        # Modulo operator or %= assignment
        # '%' already consumed above
        if @s.peek == ?=
          @s.get
          return ["%=", Operators["%="]]
        end
        return ["%", Operators["%"]]
      when ?/
        if @first || prev_lastop
          # Parse regexp literal with interpolation support
          @s.get  # consume '/'
          ret = nil
          buf = ""
          while true
            c = @s.peek
            if c == nil
              raise "Unterminated regexp"
            end
            @s.get
            if c == ?/
              # End of regexp - capture modifiers
              # Regexp options: i=1, x=2, m=4, fixedencoding=16, noencoding=32
              options = 0
              while @s.peek && (@s.peek == ?i || @s.peek == ?m || @s.peek == ?x || @s.peek == ?o || @s.peek == ?e || @s.peek == ?n || @s.peek == ?s || @s.peek == ?u)
                mod = @s.get
                case mod
                when ?i then options |= 1   # IGNORECASE
                when ?x then options |= 2   # EXTENDED
                when ?m then options |= 4   # MULTILINE
                when ?u, ?e, ?s then options |= 16  # FIXEDENCODING
                when ?n then options |= 32  # NOENCODING
                # 'o' is ignored (once-only evaluation - not relevant for us)
                end
              end
              # Finalize pattern
              if ret
                ret << buf if buf != ""
                pattern = ret
              else
                pattern = buf
              end
              return [[:callm, :Regexp, :new, [pattern, options]], nil]
            elsif c == ?\\
              # Escape sequence
              buf << c.chr
              next_c = @s.get
              buf << next_c.chr if next_c
            elsif c == ?#
              # Check for interpolation #{
              if @s.peek == ?{
                # Use Quoted.handle_interpolation helper
                result = Tokens::Quoted.handle_interpolation(@s, ret, buf) { @parser.parse_defexp }
                if result
                  ret = result
                  buf = ""
                else
                  buf << c.chr
                end
              else
                buf << c.chr
              end
            else
              buf << c.chr
            end
          end
        else
          # Division operator or /= assignment
          @s.get
          if @s.peek == ?=
            @s.get
            return ["/=", Operators["/="]]
          end
          return ["/", Operators["/"]]
        end
      when ?+
        @s.get
        # A unary + directly before a numeric literal is a no-op on the value, so drop it and let the
        # literal tokenize on its own. This mirrors the negative-literal handling for `-` below and,
        # crucially, lets a following method call bind to the literal: +2.5.round parses as
        # (+2.5).round, not +(2.5.round). (Only in prefix position -- an infix + after a value keeps
        # normal operator handling. No `**` exception is needed: +2**2 == +(2**2) either way.)
        if prev_lastop && Tokens.digit?(@s.peek)
          return [Number.expect(@s, true), nil]
        end
        if @s.peek == ?=
          @s.get
          return ["+=", Operators["+="]]
        end
        return ["+", Operators["+"]]
      when ?-
        @s.get
        # Only parse as negative number if last token was an operator (not after ')' etc.)
        # Special case: Don't create negative literal if followed by ** to fix precedence
        # e.g., -2**12 should parse as -(2**12) not (-2)**12
        if prev_lastop && Tokens.digit?(@s.peek)
          # Look ahead: consume the number and check what follows
          num_str = ""
          while Tokens.digit?(@s.peek)
            num_str << @s.get
          end
          # Skip whitespace and check for ** (a following power operator flips precedence:
          # -2**12 is -(2**12), so the sign must NOT fold into the literal there). The lookahead
          # must consume at most one '*' and restore it in every branch -- consuming a lone '*'
          # without ungetting it silently drops the multiply operator, so `-5 * x` mis-parses as
          # a call `-5(x)` (the tagged literal -5 becomes a garbage call target -> SIGSEGV).
          @s.nolfws
          star_consumed = false
          if @s.peek == ?*
            @s.get
            star_consumed = true
          end
          followed_by_power = star_consumed && @s.peek == ?*

          # Only create negative literal if NOT followed by **
          if !followed_by_power
            # Restore the single '*' the lookahead consumed above, so it is re-tokenized as the
            # multiply operator after the negative literal.
            @s.unget("*") if star_consumed
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

        # Special case: Handle anonymous splat (* = value) or (*)
        # If we see * in prefix position followed by = or ), treat as identifier :_
        if first == "*" && (@first || prev_lastop)
          # Peek ahead through whitespace to check for = or )
          ws_chars = ""
          while (wc = @s.peek) && ((wo = wc.ord) == 32 || wo == 9 || wo == 13 || wo == 10)
            ws_chars << @s.get
          end

          next_char = @s.peek
          if next_char == ?=
            # Check it's not **= or *= (compound assignment)
            equals = @s.get
            following = @s.peek
            if following && following != ?= && following != ?*
              # This is * followed by = (not *= or **=)
              # Unget everything and return :_ as identifier
              @s.unget(equals) if equals
              @s.unget(ws_chars.reverse) if ws_chars && !ws_chars.empty?
              return [:_, nil]
            end
            # It's *= or **= or something else, unget and continue
            @s.unget(equals) if equals
          elsif next_char == ?)
            # This is (*) - anonymous splat in parentheses
            # Return :_ as identifier
            @s.unget(ws_chars.reverse) if ws_chars && !ws_chars.empty?
            return [:_, nil]
          end
          # Unget whitespace and continue normal operator handling
          @s.unget(ws_chars.reverse) if ws_chars && !ws_chars.empty?
        end

        if second = @s.get
          if first == "?" and (so = second[0].chr.ord) != 32 && so != 10 && so != 9 && so != 13
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
              when "M"
                # Meta escape: \M-x or \M-\C-x or \M-\c-x
                if @s.peek == "-"
                  @s.get  # consume the dash
                  # Check if it's \M-\C- or \M-\c-
                  if @s.peek == "\\"
                    @s.get  # consume backslash
                    ctrl_char = @s.get
                    if ctrl_char == "C" || ctrl_char == "c"
                      if @s.peek == "-"
                        @s.get  # consume dash
                        ch = @s.get
                        # Meta-Control: set both bit 7 and apply control
                        return [((ch[0].chr.ord & 0x1f) | 0x80), nil]
                      end
                    end
                  else
                    # Just \M-x: set bit 7
                    ch = @s.get
                    return [(ch[0].chr.ord | 0x80), nil]
                  end
                end
              when "C", "c"
                # Control escape: \C-x or \c-x
                if @s.peek == "-"
                  @s.get  # consume the dash
                  ch = @s.get
                  # Control: mask to lower 5 bits
                  return [(ch[0].chr.ord & 0x1f), nil]
                end
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
          # Always check for heredoc pattern - will fall back to << operator if not heredoc
          if buf == "<<"
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

            # Check if next character starts an identifier or quoted heredoc marker.
            # A plain "<<IDENT" is only a heredoc in operand position (start of expression or after
            # an operator); after a value it is the shift/append operator (e.g. "r<<i"). "<<~"/"<<-"
            # are unambiguously heredocs, so they are not gated on operand position.
            if @s.peek && (ALPHA.member?(@s.peek) || @s.peek == ?_ || @s.peek == ?' || @s.peek == ?") &&
               (dash || squiggly || @first || prev_lastop)
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
                while @s.peek && (ALPHA.member?(@s.peek) || Tokens.digit?(@s.peek) || @s.peek == ?_)
                  marker << @s.get.chr
                end
              end

              # Save the rest of the line (there might be more code after the heredoc marker)
              rest_of_line = ""
              while @s.peek && @s.peek != ?\n
                rest_of_line << @s.get.chr
              end
              @s.get if @s.peek == ?\n  # consume newline

              # Read heredoc body directly from the scanner using shared
              # escape/interpolation handling from Quoted.
              interpolate = (quote_char != ?')

              if interpolate
                result = Quoted.expect_heredoc(@s, marker, squiggly) { @parser.parse_defexp }
              else
                # Single-quoted heredoc: no escape processing, read raw body
                result = Quoted.expect_heredoc_squoted(@s, marker, squiggly)
              end

              # Put back the rest of the line so it can be parsed
              @s.unget(rest_of_line) if rest_of_line && !rest_of_line.empty?

              return [result, nil]
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

    def nolfws
      @s.nolfws
    end

    attr_reader :lasttoken

    # Non-destructive lookahead used for leading-dot continuation: with the scanner positioned at a `#`
    # comment, report whether the FIRST non-blank character of the NEXT line is `.`. Uses only the
    # scanner's character primitives (peek/get/unget) and restores the position before returning.
    def comment_then_leading_dot?
      consumed = []
      while (c = @s.peek) && c != "\n"
        consumed << @s.get
      end
      result = false
      if @s.peek == "\n"
        consumed << @s.get
        while (c = @s.peek) && (c == " " || c == "\t")
          consumed << @s.get
        end
        result = (@s.peek == ".")
      end
      consumed.reverse.each {|ch| @s.unget(ch) }
      result
    end

    def get
      @lasttoken = @curtoken

      if @last.is_a?(Array) && @last[1].is_a?(Oper) && @last[1].sym == :callm
        @lastop = false
        # A "." may be followed by whitespace (including a newline) before the method name -- the
        # trailing-dot continuation "expr.\n  method". Skip it so the method name is found.
        @s.ws
        @lastpos = @s.position
        res = Methodname.expect(@s)
        # Support .() syntax for lambda/proc calls - insert :call as method name
        if !res && @s.peek == ?(
          res = :call
        elsif !res && @s.peek && @s.peek.ord == 96
          # A backtick (`) is a valid method name immediately after '.': obj.`(args). Elsewhere the
          # tokenizer treats ` as a command-string start, but in method-name position it is the name.
          # (96 == ?` -- written numerically to avoid a stray backtick in the source.)
          @s.get
          res = 96.chr.to_sym
        end
        res = [res,nil] if res
      else
        # Check if there's a newline before consuming any whitespace
        # This must be done BEFORE calling ws/nolfws as they consume the newline
        @newline_before_current = (@s.peek && @s.peek.ord == 10)

        # FIXME: This rule should likely cover more
        # cases; may want additional flags
        if @lastop && @last && @last[0] != :return
          @s.ws
        else
          @s.nolfws
          # Leading-dot method-chain continuation across a trailing comment: `foo(...) # note\n .bar`.
          # After a value, nolfws stops at the `#`; if the next line begins with `.`, the comment and
          # newline are insignificant and `.method` chains onto the value. Handled here in the tokenizer
          # alongside the trailing-dot continuation above -- the Scanner stays grammar-agnostic.
          if @s.peek == "#" && comment_then_leading_dot?
            @s.ws  # consume the comment and its newline, leaving the scanner positioned at the `.`
          end
        end

        # Parser bug fix: Track newlines for @lastop to fix negative number parsing
        # This fixes: 4.ceildiv(-3) followed by -4.ceildiv(3) on next line
        # Without this, -4 is parsed as binary subtraction instead of unary minus
        # Store boolean directly to avoid local variable issues in self-hosted compiler
        @at_newline = @s.peek ? (@s.peek.ord == 10) : false

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
      if @at_newline && old_last && old_last[1] && old_last[1].is_a?(Oper)
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
