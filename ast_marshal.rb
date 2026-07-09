# TEMPORARY / INTERIM STAGE ONLY. Purpose-built serializer for the PARSED core AST, so lib/core is
# parsed once and the AST is loaded from a cache thereafter (COREMARSHAL). It handles the closed set
# of parsed-AST types via public constructors + accessors -- NO reflection -- purely to bank the ~34%
# compile speedup NOW (which makes all further tests/dev cheaper) while the real work proceeds.
#
# THE ONGOING GOAL IS FULL Marshal (pure_ruby_marshal), NOT this. Once the compiler has dynamic-ivar
# reflection (instance_variable_get/set / instance_variables / const_get / send + the `ivar` codegen
# support) and pure_ruby_marshal is ported into lib/core, this file is to be REPLACED by that general
# Marshal (which also passes the core/marshal specs). This is a bridge, not the destination.
# See docs/coremarshal-ast/FINDINGS.md. @extra is skipped (set only during transforms, never in the
# parsed AST). Must run identically MRI-hosted and self-hosted.
require 'ast'
require 'scanner'

module ASTMarshal
  module_function

  # dump: append tagged bytes to `out` (an Array of strings, joined at the end).
  def dump(o, out)
    if o.nil?
      out << "0"
    elsif o == true
      out << "T"
    elsif o == false
      out << "F"
    elsif o.is_a?(Integer)
      s = o.to_s
      out << "i" << [s.bytesize].pack("N") << s
    elsif o.is_a?(Symbol)
      s = o.to_s
      out << "y" << [s.bytesize].pack("N") << s
    elsif o.is_a?(Scanner::ScannerString)
      out << "S" << [o.bytesize].pack("N") << o.to_s
      dump(o.position, out)
    elsif o.is_a?(Scanner::Position)
      out << "p"
      dump(o.filename, out)
      dump(o.lineno, out)
      dump(o.col, out)
    elsif o.is_a?(String)
      out << "s" << [o.bytesize].pack("N") << o
    elsif o.is_a?(AST::Expr)
      out << "e" << [o.length].pack("N")
      o.each { |e| dump(e, out) }
      dump(o.position, out)
    elsif o.is_a?(Array)
      out << "a" << [o.length].pack("N")
      o.each { |e| dump(e, out) }
    else
      raise "ASTMarshal: unhandled type #{o.class}"
    end
  end

  # load: read one tagged value from `str` at [pos]; return [obj, newpos]. `while` loops (not the
  # block form) so `pos` is a plain local, not captured/mutated through a closure.
  def load(str, pos)
    tag = str[pos]
    pos += 1
    if tag == "0"
      return nil, pos
    elsif tag == "T"
      return true, pos
    elsif tag == "F"
      return false, pos
    elsif tag == "i"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      return str[pos, n].to_i, pos + n
    elsif tag == "y"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      return str[pos, n].to_sym, pos + n
    elsif tag == "s"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      return str[pos, n], pos + n
    elsif tag == "S"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      body = str[pos, n]
      pos += n
      p, pos = load(str, pos)
      ss = Scanner::ScannerString.new(body)
      ss.position = p
      return ss, pos
    elsif tag == "p"
      f, pos = load(str, pos)
      l, pos = load(str, pos)
      c, pos = load(str, pos)
      return Scanner::Position.new(f, l, c), pos
    elsif tag == "e"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      e = AST::Expr.new
      i = 0
      while i < n
        v, pos = load(str, pos)
        e.push(v)
        i += 1
      end
      p, pos = load(str, pos)
      e.position = p
      return e, pos
    elsif tag == "a"
      n = str[pos, 4].unpack("N")[0]
      pos += 4
      arr = []
      i = 0
      while i < n
        v, pos = load(str, pos)
        arr << v
        i += 1
      end
      return arr, pos
    else
      raise "ASTMarshal: bad tag #{tag.inspect} at #{pos - 1}"
    end
  end

  def dump_str(o)
    buf = []
    dump(o, buf)
    buf.join
  end

  def load_str(s)
    o, _ = load(s, 0)
    o
  end

  # ---- cache invalidation ------------------------------------------------------------------------
  # A content checksum over every *.rb under `dir` (recursively). Order-INDEPENDENT (per-file keys are
  # summed) so it does not depend on Dir.entries order, and host-INDEPENDENT (plain byte arithmetic, no
  # MRI-only hashing) so an MRI-written cache validates identically self-hosted and vice-versa. All
  # arithmetic is masked to 20 bits every step so intermediate products stay inside a fixnum -- bignum
  # multiply is a known-broken path and would also allocate per byte. A stale cache is never used: any
  # edit to any core source changes this key, and a mismatch falls back to a full parse.
  MASK = 0xFFFFF

  # Staleness token: the mtime (epoch seconds) of the core source directory. ONE stat -- not a byte-by-byte
  # content hash over every core file, which was pathologically slow self-hosted (millions of getbyte+mul
  # iterations, dwarfing the compile it was meant to speed up). The directory mtime changes whenever a core
  # file is added, removed, or rewritten (atomic-rename saves, the common editor path) -> a mismatch falls
  # back to a full parse. It's a filesystem property, so MRI and self-hosted read the identical value.
  def core_key(dir)
    File.mtime(dir).to_i
  end

  # Read the cached AST from `path` iff it exists and its stored key matches the live core sources under
  # `dir`; otherwise nil (caller re-parses). Format: 4-byte key header (pack("N")) then the dumped AST.
  def read_cache(path, dir)
    return nil if !File.exist?(path)
    data = IO.binread(path)
    return nil if data.nil? || data.bytesize < 4
    stored = data[0, 4].unpack("N")[0]
    return nil if stored != core_key(dir)
    o, _ = load(data, 4)
    o
  end

  # Write the AST to `path` with the current core-source key header. Single-process one-shot (invoked
  # only under COREMARSHAL_DUMP), so no temp+rename dance is needed; the read path is checksum-guarded.
  def write_cache(path, dir, ast)
    buf = []
    buf << [core_key(dir)].pack("N")
    dump(ast, buf)
    IO.binwrite(path, buf.join)
  end
end
