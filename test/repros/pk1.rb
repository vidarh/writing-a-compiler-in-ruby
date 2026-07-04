# Differential pack/unpack matrix: runs under BOTH MRI and the compiled runtime
# producing identical output (bytes shown via unpack("C*"), no raw byte access).
# Usage: ruby test/repros/pk1.rb > expected; ./compile ... ; ./out/pk1 > actual; diff.

def fmtres(v)
  if v.nil?
    "nil"
  elsif v == true
    "true"
  elsif v == false
    "false"
  elsif v.is_a?(String)
    "s(" + v.unpack("C*").join(",") + ")"
  elsif v.is_a?(Array)
    parts = []
    i = 0
    while i < v.length
      parts << fmtres(v[i])
      i += 1
    end
    "[" + parts.join(",") + "]"
  else
    v.to_s
  end
end

def try_pack(fmt, arr)
  begin
    r = arr.pack(fmt)
    puts "pack #{fmt}: #{fmtres(r)}"
  rescue NotImplementedError => e
    puts "pack #{fmt}: NotImplementedError"
  rescue TypeError => e
    puts "pack #{fmt}: TypeError"
  rescue ArgumentError => e
    puts "pack #{fmt}: ArgumentError"
  rescue RangeError => e
    puts "pack #{fmt}: RangeError"
  end
end

def try_unpack(fmt, str)
  begin
    r = str.unpack(fmt)
    puts "unpack #{fmt}: #{fmtres(r)}"
  rescue NotImplementedError => e
    puts "unpack #{fmt}: NotImplementedError"
  rescue TypeError => e
    puts "unpack #{fmt}: TypeError"
  rescue ArgumentError => e
    puts "unpack #{fmt}: ArgumentError"
  end
end

# ---- integer pack ----
try_pack("C*", [65, 66, 300, 1])
try_pack("c2", [-1, -128])
try_pack("C", [255])
try_pack("s*", [1, -1, 32767, -32768])
try_pack("S2", [1, 65535])
try_pack("n*", [1, 258, 65535])
try_pack("v*", [1, 258, 65535])
try_pack("l*", [1, -1])
try_pack("L", [4294967295])
try_pack("N2", [1, 16909060])
try_pack("V2", [1, 16909060])
try_pack("j", [-2])
try_pack("J", [305419896])
try_pack("i2", [-2, 3])
try_pack("I", [4000000000])
try_pack("q", [-2])
try_pack("Q", [1311768467463790320])
try_pack("s>*", [1, -2])
try_pack("s<*", [1, -2])
try_pack("l>", [66051])
try_pack("L<", [66051])
try_pack("w*", [0, 1, 127, 128, 300, 16384])
try_pack("U*", [65, 233, 8364, 128512])
# mixed + whitespace + comment
try_pack("C2 s", [1, 2, 3])
try_pack("C # eight bit\nC", [7, 8])
# strings
try_pack("a5", ["ab"])
try_pack("A5", ["ab"])
try_pack("Z5", ["ab"])
try_pack("a*", ["hello"])
try_pack("Z*", ["hello"])
try_pack("a", ["xyz"])
try_pack("B*", ["0110000101100010"])
try_pack("b*", ["0110000101100010"])
try_pack("B11", ["01100001011"])
try_pack("H*", ["616263"])
try_pack("h*", ["616263"])
try_pack("H3", ["616"])
try_pack("m", ["hello world"])
try_pack("m0", ["hello world"])
try_pack("u", ["hello world"])
try_pack("x3C", [65])
try_pack("CCX", [65, 66])
try_pack("C@3C", [1, 2])
# errors
try_pack("R", [1])
try_pack("C2", [1])
try_pack("C", [nil])
try_pack("C", ["str"])
try_pack("d", [1])
try_pack("s!*", [5, -5])
try_pack("C!", [5])

# ---- unpack ----
try_unpack("C*", [65, 66, 200].pack("C*"))
try_unpack("c*", [65, 200].pack("C*"))
try_unpack("C5", "abc")
try_unpack("s*", [1, -1, 32767, -32768].pack("s*"))
try_unpack("S<2", [513, 65535].pack("v*"))
try_unpack("S>2", [513, 65535].pack("n*"))
try_unpack("n*", [513, 65535].pack("n*"))
try_unpack("v*", [513, 65535].pack("v*"))
try_unpack("l*", [1, -1, 2147483647, -2147483648].pack("l*"))
try_unpack("L*", [4294967295].pack("L*"))
try_unpack("N*", [1, 16909060].pack("N*"))
try_unpack("V*", [1, 16909060].pack("V*"))
try_unpack("q*", [-2, 1311768467463790320].pack("q*"))
try_unpack("Q", [18446744073709551615].pack("Q"))
try_unpack("j", [-2].pack("j"))
try_unpack("i*", [-2, 3].pack("i*"))
try_unpack("N", "ab")
try_unpack("w*", [0, 1, 127, 128, 300, 16384].pack("w*"))
try_unpack("U*", [65, 233, 8364, 128512].pack("U*"))
try_unpack("a*", "hello")
try_unpack("a3a*", "hello")
try_unpack("A5", "ab \x00")
try_unpack("A*", "ab  ")
try_unpack("Z*", [104, 105, 0, 106].pack("C*"))
try_unpack("Z3", [104, 0, 105].pack("C*"))
try_unpack("B*", "ab")
try_unpack("b*", "ab")
try_unpack("B11", "ab")
try_unpack("H*", "abc")
try_unpack("h*", "abc")
try_unpack("m", ["hello world"].pack("m"))
try_unpack("m", ["hello worl"].pack("m"))
try_unpack("m", ["hello wor"].pack("m"))
try_unpack("u", ["hello world"].pack("u"))
try_unpack("x2C", [1, 2, 3].pack("C*"))
try_unpack("C2X2C2", [1, 2].pack("C*"))
try_unpack("@2C", [1, 2, 3].pack("C*"))
try_unpack("x5", "abc")
try_unpack("R", "abc")
try_unpack("d", "abcdefgh")
try_unpack("C2 # comment\nC", [9, 8, 7].pack("C*"))
