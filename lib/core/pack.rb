# Shared byte codec behind Array#pack and String#unpack.
#
# Strings are byte-oriented in this runtime (s[i] is a byte VALUE), which is
# exactly what pack/unpack want. All engines work on byte codes.
#
# Directive coverage: C c S s L l Q q N n V v J j I i w U  (integers),
# a A Z b B h H m u (strings), x X @ (position). Endian modifiers < >,
# native-size modifiers ! _ (no-ops here: ILP32). Float directives
# (d e E f g G) raise NotImplementedError until Float lands; p/P raise
# ArgumentError like MRI.
class __Pack
  # --- format iteration -----------------------------------------------------
  # Yields nothing; returns an array of [directive_byte, count, star, big_endian]
  # tuples. Whitespace and '#'-to-EOL comments are skipped. Unknown directives
  # raise ArgumentError (MRI message shape).
  def self.parse_format(fmt)
    out = []
    fi = 0
    flen = fmt.length
    while fi < flen
      d = fmt[fi]
      fi += 1
      # skip whitespace / NUL between directives
      if d == 32 || d == 9 || d == 10 || d == 13 || d == 12 || d == 11 || d == 0
        next
      end
      # '#' comment runs to end of line
      if d == 35
        while fi < flen && fmt[fi] != 10
          fi += 1
        end
        next
      end
      if !directive?(d)
        raise ArgumentError, "unknown pack directive '#{d.chr}' in '#{fmt}'"
      end
      # modifiers: '!' '_' (native size; no-op) and '<' '>' (endianness)
      big = nil
      while fi < flen && (fmt[fi] == 33 || fmt[fi] == 95 || fmt[fi] == 60 || fmt[fi] == 62)
        mod = fmt[fi]
        if mod == 33 || mod == 95
          if !bang_ok?(d)
            raise ArgumentError, "'#{mod.chr}' allowed only after types sSiIlLqQjJ"
          end
        else
          if !endian_ok?(d)
            raise ArgumentError, "'#{mod.chr}' allowed only after types sSiIlLqQjJ"
          end
          big = (mod == 62)
        end
        fi += 1
      end
      # count: digits or '*'
      count = nil
      star = false
      if fi < flen && fmt[fi] == 42
        star = true
        fi += 1
      elsif fi < flen && fmt[fi] >= 48 && fmt[fi] <= 57
        count = 0
        while fi < flen && fmt[fi] >= 48 && fmt[fi] <= 57
          count = count * 10 + (fmt[fi] - 48)
          fi += 1
        end
      end
      out << [d, count, star, big]
    end
    out
  end

  def self.directive?(d)
    # C c S s L l Q q N n V v J j I i w U a A Z b B h H m u x X @ d e E f g G p P
    "CcSsLlQqNnVvJjIiwUaAZbBhHmuxX@deEfgGpP".b_include?(d)
  end

  def self.bang_ok?(d)
    "sSiIlLqQjJ".b_include?(d)
  end

  def self.endian_ok?(d)
    "sSiIlLqQjJ".b_include?(d)
  end

  # size in bytes / signedness / default endianness (true = big) per integer directive
  def self.int_size(d)
    return 1 if d == 67 || d == 99                    # C c
    return 2 if d == 83 || d == 115 || d == 110 || d == 118  # S s n v
    return 8 if d == 81 || d == 113                   # Q q
    4                                                  # L l N V J j I i
  end

  def self.int_signed?(d)
    d == 99 || d == 115 || d == 108 || d == 113 || d == 106 || d == 105  # c s l q j i
  end

  # nil = native (little on x86); n/N are big; v/V little; <> already resolved by caller
  def self.int_big?(d, big)
    return big if !big.nil?
    return true if d == 78 || d == 110    # N n
    false
  end

  def self.int_directive?(d)
    d == 67 || d == 99 || d == 83 || d == 115 || d == 76 || d == 108 ||
      d == 81 || d == 113 || d == 78 || d == 110 || d == 86 || d == 118 ||
      d == 74 || d == 106 || d == 73 || d == 105
  end

  # --- integer byte emit/read ----------------------------------------------
  # Append `size` bytes of the two's-complement representation of v to out.
  def self.emit_int(out, v, size, big)
    m = 256 ** size
    v = v % m           # Ruby %: non-negative result -> two's complement for negatives
    if big
      shift = size - 1
      while shift >= 0
        out << ((v / (256 ** shift)) % 256).chr
        shift -= 1
      end
    else
      k = 0
      while k < size
        out << (v % 256).chr
        v = v / 256
        k += 1
      end
    end
    nil
  end

  # Float directives: d D E G are 8-byte doubles; f F e g are 4-byte singles. d D f F are native
  # (little-endian on x86), e E little-endian, g G big-endian.
  def self.float_size(d)
    return 8 if d == 100 || d == 68 || d == 69 || d == 71   # d D E G
    4                                                       # f F e g
  end

  def self.float_big?(d)
    d == 103 || d == 71   # g G are big-endian; the rest native/little-endian on x86
  end

  # The i-th packed byte of `f` (little-endian native), as a 0..255 Integer.
  # Read byte i (0..7) of the raw bytes previously stored in scratch buffer `buf` (an __array).
  def self.__bufbyte(buf, i)
    r = 0
    %s(assign r (__int (bindex buf (sar i))))
    r
  end

  # Append the `size`-byte packed representation of val (coerced to Float) to out, big-endian if `big`.
  # x87 fstored/fstores writes the double / narrowed single into a scratch array; bindex reads its bytes.
  def self.emit_float(out, val, size, big)
    f = val.to_f
    buf = 0
    %s(assign buf (__array 2))
    if size == 8
      %s(fstored f buf)
    else
      %s(fstores f buf)
    end
    k = 0
    while k < size
      idx = big ? (size - 1 - k) : k
      out << __bufbyte(buf, idx).chr
      k += 1
    end
    nil
  end

  # Read a `size`-byte packed float at str[pos] into a Float (big-endian if `big`). nil if too few bytes.
  # Assemble the bytes into a binary-safe String in little-endian order, then x87 floadd/floads reads its
  # buffer into the Float (flds widens a single to double).
  def self.read_float(str, pos, size, big)
    return nil if pos + size > str.length
    buf = ""
    k = 0
    while k < size
      idx = big ? (size - 1 - k) : k
      buf << str[pos + idx].chr
      k += 1
    end
    r = Float.new
    if size == 8
      %s(floadd (callm buf __get_raw) r)
    else
      %s(floads (callm buf __get_raw) r)
    end
    r
  end

  # Read `size` bytes at str[pos] as an integer. Returns nil if not enough bytes.
  def self.read_int(str, pos, size, big, signed)
    return nil if pos + size > str.length
    v = 0
    if big
      k = 0
      while k < size
        v = v * 256 + str[pos + k]
        k += 1
      end
    else
      k = size - 1
      while k >= 0
        v = v * 256 + str[pos + k]
        k -= 1
      end
    end
    if signed
      half = 256 ** size / 2
      if v >= half
        v = v - 256 ** size
      end
    end
    v
  end

  # Coerce a pack element to Integer per MRI rules (to_int; nil/String get TypeError).
  def self.to_int_strict(obj)
    if obj.nil?
      raise TypeError, "no implicit conversion from nil to integer"
    end
    if obj.is_a?(Integer)
      return obj
    end
    if obj.is_a?(String)
      raise TypeError, "no implicit conversion of String into Integer"
    end
    if obj.respond_to?(:to_int)
      r = obj.to_int
      if r.is_a?(Integer)
        return r
      end
    end
    raise TypeError, "can't convert #{obj.class} into Integer"
  end

  def self.to_str_strict(obj)
    return "" if obj.nil?
    if obj.is_a?(String)
      return obj
    end
    if obj.respond_to?(:to_str)
      r = obj.to_str
      if r.is_a?(String)
        return r
      end
    end
    raise TypeError, "no implicit conversion of #{obj.class} into String"
  end

  # --- pack ------------------------------------------------------------------
  def self.pack(arr, fmt)
    dirs = parse_format(fmt)
    out = ""
    i = 0     # element index
    di = 0
    while di < dirs.length
      dir = dirs[di]
      di += 1
      d = dir[0]
      count = dir[1]
      star = dir[2]
      big = dir[3]

      if int_directive?(d)
        size = int_size(d)
        bigflag = int_big?(d, big)
        cnt = 1
        cnt = count if count
        cnt = arr.length - i if star
        j = 0
        while j < cnt
          raise ArgumentError, "too few arguments" if i >= arr.length
          emit_int(out, to_int_strict(arr[i]), size, bigflag)
          i += 1
          j += 1
        end
      elsif d == 85              # 'U' utf-8 codepoints
        cnt = 1
        cnt = count if count
        cnt = arr.length - i if star
        j = 0
        while j < cnt
          raise ArgumentError, "too few arguments" if i >= arr.length
          cp = to_int_strict(arr[i])
          raise RangeError, "pack(U): value out of range" if cp < 0
          emit_utf8(out, cp)
          i += 1
          j += 1
        end
      elsif d == 119             # 'w' BER-compressed
        cnt = 1
        cnt = count if count
        cnt = arr.length - i if star
        j = 0
        while j < cnt
          raise ArgumentError, "too few arguments" if i >= arr.length
          v = to_int_strict(arr[i])
          raise ArgumentError, "can't compress negative numbers" if v < 0
          emit_ber(out, v)
          i += 1
          j += 1
        end
      elsif d == 97 || d == 65 || d == 90    # 'a' 'A' 'Z'
        raise ArgumentError, "too few arguments" if i >= arr.length
        s = to_str_strict(arr[i])
        i += 1
        pad = 0
        pad = 32 if d == 65
        if star
          out << s
          out << 0.chr if d == 90    # Z* appends the NUL
        else
          cnt = 1
          cnt = count if count
          k = 0
          while k < cnt
            if k < s.length
              out << s[k].chr
            else
              out << pad.chr
            end
            k += 1
          end
        end
      elsif d == 66 || d == 98    # 'B' (msb first) / 'b' (lsb first)
        raise ArgumentError, "too few arguments" if i >= arr.length
        s = to_str_strict(arr[i])
        i += 1
        cnt = 1
        cnt = count if count
        cnt = s.length if star
        emit_bits(out, s, cnt, d == 66)
      elsif d == 72 || d == 104   # 'H' (high nibble first) / 'h'
        raise ArgumentError, "too few arguments" if i >= arr.length
        s = to_str_strict(arr[i])
        i += 1
        cnt = 1
        cnt = count if count
        cnt = s.length if star
        emit_hex(out, s, cnt, d == 72)
      elsif d == 109              # 'm' base64
        raise ArgumentError, "too few arguments" if i >= arr.length
        s = to_str_strict(arr[i])
        i += 1
        width = 60
        width = 0 if count && count == 0
        raise ArgumentError, "invalid base64" if count && count > 0 && count < 3
        emit_base64(out, s, width)
      elsif d == 117              # 'u' uuencode
        raise ArgumentError, "too few arguments" if i >= arr.length
        s = to_str_strict(arr[i])
        i += 1
        emit_uu(out, s)
      elsif d == 120              # 'x' null byte(s)
        cnt = 1
        cnt = count if count
        cnt = 0 if star
        k = 0
        while k < cnt
          out << 0.chr
          k += 1
        end
      elsif d == 88               # 'X' back up
        cnt = 1
        cnt = count if count
        cnt = 0 if star
        raise ArgumentError, "X outside of string" if cnt > out.length
        out = out[0, out.length - cnt]
      elsif d == 64               # '@' absolute position
        target = 1
        target = count if count
        target = 0 if star
        if target <= out.length
          out = out[0, target]
        else
          k = out.length
          while k < target
            out << 0.chr
            k += 1
          end
        end
      elsif d == 100 || d == 68 || d == 101 || d == 69 || d == 102 || d == 70 || d == 103 || d == 71
        # d D e E f F g G: Float directives -- IEEE-754 bytes of the (coerced) Float.
        size = float_size(d)
        bigflag = float_big?(d)
        cnt = 1
        cnt = count if count
        cnt = arr.length - i if star
        j = 0
        while j < cnt
          raise ArgumentError, "too few arguments" if i >= arr.length
          emit_float(out, arr[i], size, bigflag)
          i += 1
          j += 1
        end
      elsif d == 112 || d == 80   # 'p' 'P' pointers
        raise ArgumentError, "'#{d.chr}' is not allowed in this implementation"
      end
    end
    out
  end

  # --- unpack ----------------------------------------------------------------
  def self.unpack(str, fmt)
    dirs = parse_format(fmt)
    res = []
    pos = 0
    blen = str.length
    di = 0
    while di < dirs.length
      dir = dirs[di]
      di += 1
      d = dir[0]
      count = dir[1]
      star = dir[2]
      big = dir[3]

      if int_directive?(d)
        size = int_size(d)
        bigflag = int_big?(d, big)
        signed = int_signed?(d)
        if star
          while pos + size <= blen
            res << read_int(str, pos, size, bigflag, signed)
            pos += size
          end
        else
          cnt = 1
          cnt = count if count
          j = 0
          while j < cnt
            v = read_int(str, pos, size, bigflag, signed)
            res << v                # nil when out of data (MRI pads with nil)
            pos += size if v != nil
            pos = blen if v.nil?
            j += 1
          end
        end
      elsif d == 85               # 'U'
        cnt = -1
        cnt = count if count
        cnt = -1 if star
        n = 0
        while pos < blen && (cnt < 0 || n < cnt)
          pair = read_utf8(str, pos)
          break if pair.nil?
          res << pair[0]
          pos = pair[1]
          n += 1
        end
        if cnt > 0
          while n < cnt
            res << nil
            n += 1
          end
        end
      elsif d == 119              # 'w'
        cnt = -1
        cnt = count if count
        cnt = -1 if star
        n = 0
        while pos < blen && (cnt < 0 || n < cnt)
          v = 0
          while pos < blen
            b = str[pos]
            pos += 1
            v = v * 128 + (b % 128)
            break if b < 128
          end
          res << v
          n += 1
        end
      elsif d == 97               # 'a' raw bytes
        if star
          res << str[pos, blen - pos].to_s
          pos = blen
        else
          cnt = 1
          cnt = count if count
          cnt = blen - pos if cnt > blen - pos
          res << str[pos, cnt].to_s
          pos += cnt
        end
      elsif d == 65               # 'A' strip trailing spaces/NULs
        if star
          s = str[pos, blen - pos].to_s
          pos = blen
        else
          cnt = 1
          cnt = count if count
          cnt = blen - pos if cnt > blen - pos
          s = str[pos, cnt].to_s
          pos += cnt
        end
        e = s.length - 1
        while e >= 0 && (s[e] == 32 || s[e] == 0)
          e -= 1
        end
        res << s[0, e + 1].to_s
      elsif d == 90               # 'Z' up to NUL
        if star
          s = ""
          while pos < blen && str[pos] != 0
            s << str[pos].chr
            pos += 1
          end
          pos += 1 if pos < blen   # consume the NUL
          res << s
        else
          cnt = 1
          cnt = count if count
          cnt = blen - pos if cnt > blen - pos
          raw = str[pos, cnt].to_s
          pos += cnt
          z = raw.index(0.chr)
          if z
            res << raw[0, z].to_s
          else
            res << raw
          end
        end
      elsif d == 66 || d == 98    # 'B' 'b' bits
        cnt = 1
        cnt = count if count
        cnt = (blen - pos) * 8 if star
        res << read_bits(str, pos, cnt, d == 66)
        pos += (cnt + 7) / 8
        pos = blen if pos > blen
      elsif d == 72 || d == 104   # 'H' 'h' nibbles
        cnt = 1
        cnt = count if count
        cnt = (blen - pos) * 2 if star
        res << read_hex(str, pos, cnt, d == 72)
        pos += (cnt + 1) / 2
        pos = blen if pos > blen
      elsif d == 109              # 'm' base64 decode
        s = str[pos, blen - pos].to_s
        pos = blen
        res << decode_base64(s)
      elsif d == 117              # 'u' uudecode
        s = str[pos, blen - pos].to_s
        pos = blen
        res << decode_uu(s)
      elsif d == 120              # 'x' skip forward
        cnt = 1
        cnt = count if count
        cnt = blen - pos if star
        raise ArgumentError, "x outside of string" if pos + cnt > blen
        pos += cnt
      elsif d == 88               # 'X' back up
        cnt = 1
        cnt = count if count
        cnt = 0 if star
        raise ArgumentError, "X outside of string" if cnt > pos
        pos -= cnt
      elsif d == 64               # '@'
        target = 1
        target = count if count
        target = blen if star
        raise ArgumentError, "@ outside of string" if target > blen
        pos = target
      elsif d == 100 || d == 68 || d == 101 || d == 69 || d == 102 || d == 70 || d == 103 || d == 71
        # d D e E f F g G: reconstruct Floats from IEEE-754 bytes.
        size = float_size(d)
        bigflag = float_big?(d)
        if star
          while pos + size <= blen
            res << read_float(str, pos, size, bigflag)
            pos += size
          end
        else
          cnt = 1
          cnt = count if count
          j = 0
          while j < cnt
            v = read_float(str, pos, size, bigflag)
            res << v
            pos += size if v != nil
            pos = blen if v.nil?
            j += 1
          end
        end
      elsif d == 112 || d == 80
        raise ArgumentError, "'#{d.chr}' is not allowed in this implementation"
      end
    end
    res
  end

  # --- helpers ----------------------------------------------------------------
  def self.emit_utf8(out, cp)
    if cp < 128
      out << cp.chr
    elsif cp < 2048
      out << (192 + cp / 64).chr
      out << (128 + cp % 64).chr
    elsif cp < 65536
      out << (224 + cp / 4096).chr
      out << (128 + (cp / 64) % 64).chr
      out << (128 + cp % 64).chr
    else
      out << (240 + cp / 262144).chr
      out << (128 + (cp / 4096) % 64).chr
      out << (128 + (cp / 64) % 64).chr
      out << (128 + cp % 64).chr
    end
    nil
  end

  # Returns [codepoint, newpos] or nil on invalid/truncated sequence.
  def self.read_utf8(str, pos)
    b0 = str[pos]
    return [b0, pos + 1] if b0 < 128
    if b0 >= 192 && b0 < 224
      n = 1
      cp = b0 - 192
    elsif b0 >= 224 && b0 < 240
      n = 2
      cp = b0 - 224
    elsif b0 >= 240 && b0 < 248
      n = 3
      cp = b0 - 240
    else
      return nil
    end
    k = 1
    while k <= n
      return nil if pos + k >= str.length
      b = str[pos + k]
      return nil if b < 128 || b >= 192
      cp = cp * 64 + (b - 128)
      k += 1
    end
    [cp, pos + n + 1]
  end

  def self.emit_ber(out, v)
    # big-endian 7-bit groups, high bit set on all but the last
    bytes = []
    bytes << v % 128
    v = v / 128
    while v > 0
      bytes << v % 128 + 128
      v = v / 128
    end
    k = bytes.length - 1
    while k >= 0
      out << bytes[k].chr
      k -= 1
    end
    nil
  end

  def self.emit_bits(out, s, cnt, msb_first)
    cnt = s.length if cnt > s.length
    k = 0
    while k < cnt
      nbits = cnt - k
      nbits = 8 if nbits > 8
      byte = 0
      j = 0
      while j < nbits
        bit = s[k + j] % 2      # MRI uses the low bit of the character
        if msb_first
          byte = byte + bit * (2 ** (7 - j))
        else
          byte = byte + bit * (2 ** j)
        end
        j += 1
      end
      out << byte.chr
      k += 8
    end
    nil
  end

  def self.read_bits(str, pos, cnt, msb_first)
    s = ""
    avail = (str.length - pos) * 8
    cnt = avail if cnt > avail
    k = 0
    while k < cnt
      byte = str[pos + k / 8]
      if msb_first
        bit = (byte / (2 ** (7 - k % 8))) % 2
      else
        bit = (byte / (2 ** (k % 8))) % 2
      end
      s << (48 + bit).chr
      k += 1
    end
    s
  end

  def self.hexval(c)
    return c - 48 if c >= 48 && c <= 57
    return c - 87 if c >= 97 && c <= 102
    return c - 55 if c >= 65 && c <= 70
    0
  end

  def self.hexchr(v)
    return (48 + v).chr if v < 10
    (87 + v).chr
  end

  def self.emit_hex(out, s, cnt, high_first)
    cnt = s.length if cnt > s.length
    byte = 0
    n = 0
    k = 0
    while k < cnt
      v = hexval(s[k])
      if high_first
        byte = byte * 16 + v
      else
        if n == 0
          byte = v
        else
          byte = byte + v * 16
        end
      end
      n += 1
      if n == 2
        out << byte.chr
        byte = 0
        n = 0
      end
      k += 1
    end
    if n == 1
      if high_first
        out << (byte * 16).chr
      else
        out << byte.chr
      end
    end
    nil
  end

  def self.read_hex(str, pos, cnt, high_first)
    s = ""
    avail = (str.length - pos) * 2
    cnt = avail if cnt > avail
    k = 0
    while k < cnt
      byte = str[pos + k / 2]
      if high_first
        if k % 2 == 0
          s << hexchr(byte / 16)
        else
          s << hexchr(byte % 16)
        end
      else
        if k % 2 == 0
          s << hexchr(byte % 16)
        else
          s << hexchr(byte / 16)
        end
      end
      k += 1
    end
    s
  end

  B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

  def self.emit_base64(out, s, width)
    line = 0
    k = 0
    slen = s.length
    while k < slen
      b0 = s[k]
      b1 = nil
      b2 = nil
      b1 = s[k + 1] if k + 1 < slen
      b2 = s[k + 2] if k + 2 < slen
      out << B64CHARS[b0 / 4].chr
      if b1.nil?
        out << B64CHARS[(b0 % 4) * 16].chr
        out << 61.chr << 61.chr
      elsif b2.nil?
        out << B64CHARS[(b0 % 4) * 16 + b1 / 16].chr
        out << B64CHARS[(b1 % 16) * 4].chr
        out << 61.chr
      else
        out << B64CHARS[(b0 % 4) * 16 + b1 / 16].chr
        out << B64CHARS[(b1 % 16) * 4 + b2 / 64].chr
        out << B64CHARS[b2 % 64].chr
      end
      k += 3
      line += 4
      if width > 0 && (line >= width || k >= slen)
        out << 10.chr
        line = 0
      end
    end
    nil
  end

  def self.b64val(c)
    return c - 65 if c >= 65 && c <= 90     # A-Z
    return c - 71 if c >= 97 && c <= 122    # a-z -> 26..51
    return c + 4 if c >= 48 && c <= 57      # 0-9 -> 52..61
    return 62 if c == 43                    # +
    return 63 if c == 47                    # /
    -1
  end

  def self.decode_base64(s)
    out = ""
    acc = []
    k = 0
    while k < s.length
      v = b64val(s[k])
      if v >= 0
        acc << v
        if acc.length == 4
          out << (acc[0] * 4 + acc[1] / 16).chr
          out << ((acc[1] % 16) * 16 + acc[2] / 4).chr
          out << ((acc[2] % 4) * 64 + acc[3]).chr
          acc = []
        end
      end
      k += 1
    end
    if acc.length == 3
      out << (acc[0] * 4 + acc[1] / 16).chr
      out << ((acc[1] % 16) * 16 + acc[2] / 4).chr
    elsif acc.length == 2
      out << (acc[0] * 4 + acc[1] / 16).chr
    end
    out
  end

  def self.emit_uu(out, s)
    k = 0
    slen = s.length
    while k < slen
      n = slen - k
      n = 45 if n > 45
      out << (32 + n).chr
      j = 0
      while j < n
        b0 = s[k + j]
        b1 = 0
        b2 = 0
        b1 = s[k + j + 1] if k + j + 1 < slen && j + 1 < n
        b2 = s[k + j + 2] if k + j + 2 < slen && j + 2 < n
        out << uuchr(b0 / 4)
        out << uuchr((b0 % 4) * 16 + b1 / 16)
        out << uuchr((b1 % 16) * 4 + b2 / 64)
        out << uuchr(b2 % 64)
        j += 3
      end
      out << 10.chr
      k += n
    end
    nil
  end

  def self.uuchr(v)
    return 96.chr if v == 0
    (32 + v).chr
  end

  def self.uuval(c)
    (c - 32) % 64
  end

  def self.decode_uu(s)
    out = ""
    pos = 0
    slen = s.length
    while pos < slen
      n = uuval(s[pos])
      pos += 1
      break if n == 0
      got = 0
      while got < n && pos < slen
        c0 = 0
        c1 = 0
        c2 = 0
        c3 = 0
        c0 = uuval(s[pos]) if pos < slen
        c1 = uuval(s[pos + 1]) if pos + 1 < slen
        c2 = uuval(s[pos + 2]) if pos + 2 < slen
        c3 = uuval(s[pos + 3]) if pos + 3 < slen
        pos += 4
        out << (c0 * 4 + c1 / 16).chr
        got += 1
        if got < n
          out << ((c1 % 16) * 16 + c2 / 4).chr
          got += 1
        end
        if got < n
          out << ((c2 % 4) * 64 + c3).chr
          got += 1
        end
      end
      # skip to end of line
      while pos < slen && s[pos] != 10
        pos += 1
      end
      pos += 1
    end
    out
  end
end

class String
  # True when this string's BYTES include the byte value b. (Helper for __Pack;
  # String#include? takes a substring, this takes a byte code.)
  def b_include?(b)
    k = 0
    l = length
    while k < l
      return true if self[k] == b
      k += 1
    end
    false
  end
end
