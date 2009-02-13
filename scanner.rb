
# The purpose of the Scanner is to present a narrow interface to read characters from, with support for lookahead / unget.
# Why not StringScanner? Well, it's a Ruby C-extension, and I want to get the compiler self-hosted as soon as possible,
# so I'm sticking to something simple. The code below is sufficient to write recursive descent parsers in a pretty
# concise style in Ruby
class Scanner
  def initialize io
    @io = io
    @buf = ""
  end

  def fill
    if @buf.empty?
      c = @io.getc
      c = c.chr if c
      @buf = c ? c.to_s : ""
    end
  end

  def peek
    fill
    return @buf[-1]
  end
    
  def get
    fill
    return @buf.slice!(-1,1)
  end

  def unget(c)
    c = c.reverse if c.is_a?(String)
    @buf += c
  end

  def expect(str)
    return true if str == ""
    buf = ""
    str.each_byte do |s|
      c = peek
      if !c || c.to_i != s 
        unget(buf)
        return false
      end
      buf += get
    end
    return true
  end
end
