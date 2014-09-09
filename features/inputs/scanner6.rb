
class ScannerString < String
  def position= newp
    @position = newp
  end

  def position
    @position
  end

  def is_a? c
    # FIXME:
    # Temp hack to make Scanner#unget work
    return true
  end
end

class Position
  def initialize filename,lineno,col
    @filename = filename
    @lineno = lineno
    @col = col
  end

  def lineno
    @lineno
  end

  def col
    @col
  end

  def filename
    @filename
  end

  def inspect
    "line #{self.lineno}, col #{self.col} in #{self.filename}"
  end

  def to_s
    inspect
  end
end

class Scanner
  def initialize(io)

    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, indicate it comes from a stream

    @io = io
    @buf = ""
    @lineno = 1
    @col = 1

    if io.is_a?(File) && File.file?(io)
      @filename = File.expand_path(io.path)
    else
      @filename = "<stream>"
    end
  end

  def position 
    pos = Position.new(@filename,@lineno,@col)
    pos
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

  def unget c
    if c.is_a?(String)
      c = c.reverse
      @col = @col - c.length
      ten = 10 # FIXME: This is a temporary hack to get the compiler linking
      @lineno = @lineno - c.count(ten.chr)
    else
      puts "X"
      @col = @col - 1
    end
#    if c.respond_to?(:position) and pos = c.position
#      @lineno = pos.lineno
#      @filename = pos.filename
#      @col = pos.filename
#    else
      #STDERR.puts "unget without position: #{c}"
#    end
    @buf << c
  end
  
  def get
    fill

    pos = self.position
    ch = @buf.slice!(-1,1)
# FIXME: += translates to "incr" primitive, which is a low level instrucion
    @col = @col + 1

    if ch == "\n"
      @lineno = @lineno + 1
      @col = 1
    end

    if ch.nil?
      return nil 
    end

    s = ScannerString.new(ch)

    pos = self.position

    s.position = pos
    return s
  end



  # If &block is passed, it is a callback to parse an expression
  # that will be passed on to the method.
  def expect(str)
    return buf if str == ""
    # FIXME
#    return str.expect(self,&block) if str.respond_to?(:expect)

    str = str.to_s
    buf = ScannerString.new

    # FIXME: This fails.
    #buf.position = self.position
    # puts "each byte"

    str.each_byte do |s|
      c = peek

      ung = !c || c.chr.ord != s
      # FIXME: If I inline the expression directly below, it breaks (typing, presumably)
      if ung
        if !buf.empty?
          unget(buf) 
        end

        return false
      end
      buf << get
    end
    return buf
  end

end

s = Scanner.new(STDIN)

c = s.peek
puts "Got: #{c} (PEEK)"
c = s.get
puts "Got: #{c} (GET)"
puts "Got: #{s.get} (GET2)"

#puts
c = s.expect(:rescue)
puts c

s.unget("foo")
puts s.get
puts s.get
puts s.get

#puts s.expect(:rescue)
puts "DONE"
