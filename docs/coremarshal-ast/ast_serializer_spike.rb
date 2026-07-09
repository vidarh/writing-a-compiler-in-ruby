# AST marshal spike (pure-Ruby, no reflection) — COREMARSHAL path B.
#
# Serializes the PARSED core AST (Expr/Position/ScannerString/Array/String/Symbol/Integer/nil/bool)
# via constructors + accessors only — so it can eventually run in the self-hosted compiler (unlike
# pure_ruby_marshal, which needs instance_variable_get/set that lib/core lacks). @extra is skipped
# (set only during transforms, never in the parsed AST).
#
# Opt-in like coremarshal_patch: COREMARSHAL_AST=<cachefile> ruby -r./this driver.rb ...
require 'compiler'  # loads Scanner/AST/Parser

module ASTMarshal
  module_function

  # ---- dump: append tagged bytes to `out` (an array of strings, joined at the end) ----
  def dump(o, out)
    if o.nil?
      out << "0"
    elsif o == true
      out << "T"
    elsif o == false
      out << "F"
    elsif o.is_a?(Integer)
      s = o.to_s; out << "i" << [s.bytesize].pack("N") << s
    elsif o.is_a?(Symbol)
      s = o.to_s; out << "y" << [s.bytesize].pack("N") << s
    elsif o.is_a?(Scanner::ScannerString)
      out << "S" << [o.bytesize].pack("N") << o.to_s
      dump(o.position, out)         # Position or nil
    elsif o.is_a?(Scanner::Position)
      out << "p"
      dump(o.filename, out); dump(o.lineno, out); dump(o.col, out)
    elsif o.is_a?(String)
      out << "s" << [o.bytesize].pack("N") << o
    elsif o.is_a?(AST::Expr)
      out << "e" << [o.length].pack("N")
      o.each { |e| dump(e, out) }
      dump(o.position, out)         # Position or nil
    elsif o.is_a?(Array)
      out << "a" << [o.length].pack("N")
      o.each { |e| dump(e, out) }
    else
      raise "ASTMarshal: unhandled type #{o.class}"
    end
  end

  # ---- load: read one tagged value from `str` starting at [pos]; return [obj, newpos] ----
  def load(str, pos)
    tag = str[pos]; pos += 1
    case tag
    when "0" then [nil, pos]
    when "T" then [true, pos]
    when "F" then [false, pos]
    when "i"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      [str[pos, n].to_i, pos + n]
    when "y"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      [str[pos, n].to_sym, pos + n]
    when "s"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      [str[pos, n], pos + n]
    when "S"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      body = str[pos, n]; pos += n
      p, pos = load(str, pos)
      ss = Scanner::ScannerString.new(body); ss.position = p; [ss, pos]
    when "p"
      f, pos = load(str, pos); l, pos = load(str, pos); c, pos = load(str, pos)
      [Scanner::Position.new(f, l, c), pos]
    when "e"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      e = AST::Expr.new       # empty Expr (Array subclass); push preserves the Expr type + contents
      n.times { v, pos = load(str, pos); e.push(v) }
      p, pos = load(str, pos)
      e.position = p; [e, pos]
    when "a"
      n = str[pos, 4].unpack("N")[0]; pos += 4
      arr = []
      n.times { v, pos = load(str, pos); arr << v }
      [arr, pos]
    else
      raise "ASTMarshal: bad tag #{tag.inspect} at #{pos - 1}"
    end
  end

  def dump_str(o); buf = []; dump(o, buf); buf.join; end
  def load_str(s); o, _ = load(s, 0); o; end
end

# Hook: cache core/core.rb's parsed AST via the custom serializer.
class Parser
  if ENV["COREMARSHAL_AST"]
    alias_method :__orig_require_am, :require
    def require(q)
      cache = ENV["COREMARSHAL_AST"]
      if q == "core/core.rb" && cache && File.exist?(cache)
        return ASTMarshal.load_str(File.binread(cache))
      end
      e = __orig_require_am(q)
      if q == "core/core.rb" && cache && !File.exist?(cache)
        File.binwrite(cache, ASTMarshal.dump_str(e))
      end
      e
    end
  end
end
