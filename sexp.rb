require 'scanner'
require 'pp'

# Simple Recursive-Descent s-expression parser
class SEXParser
  def initialize s
    @s = s # The scanner
  end

  def ws
    while (c = @s.peek) && [9,10,13,32].member?(c) do @s.get; end
  end

  def parse_escaped
    return nil if @s.peek == ?"
    if @s.expect("\\")
      raised "Unexpected EOF" if !@s.peek
      return "\\"+@s.get 
    end
    return @s.get
  end

  def parse_quoted
    return nil if !@s.expect('"')
    buf = ""
    while (e = parse_escaped); buf += e; end
    raise "Unterminated string" if !@s.expect('"')
    return buf
  end

  def parse_int
    tmp = ""
    tmp += @s.get if @s.peek == ?-
    while (c = @s.peek) && (?0 .. ?9).member?(c)
      tmp += @s.get
    end
    return nil if tmp == ""
    tmp.to_i
  end

  def parse_atom
    tmp = ""
    if (c = @s.peek) && ((?a .. ?z).member?(c) || (?A .. ?Z).member?(c))
      tmp += @s.get
      
      while (c = @s.peek) && ((?a .. ?z).member?(c) || 
                                (?A .. ?Z).member?(c) || 
                                (?0 .. ?9).member?(c) || ?_ == c)
        tmp += @s.get
      end
    end
    return nil if tmp == ""
    return tmp.to_sym
  end

  def parse_sexp
    return nil if !@s.expect("(")
    ws
    raise "Expected expression" if !(exp = parse_exp)
    exprs = [exp]
    while exp = parse_exp
      exprs << exp
    end
    raise "Expected ')'" if !@s.expect(")")
    return exprs
  end

  def parse_exp
    (ret = parse_atom || parse_int || parse_quoted || parse_sexp) && ws
    return ret
  end

  def parse
    ws
    return nil if !@s.expect("%s")
    return parse_sexp || raise("Expected s-expression")
  end
end

s = Scanner.new(STDIN)
begin
  PP.pp SEXParser.new(s).parse
rescue Exception => e
  PP.pp e
  buf = ""
  while s.peek
    buf += s.get
  end
  puts buf
end

