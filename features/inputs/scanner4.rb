
class ScannerString < String
  def initialize
    @position = 0
  end

  def position= newp
    @position = newp
  end

  def position
    @position
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
# Works:
#    puts self.lineno
#    puts self.filename
# FIXME: Seg faults
#    "line #{self.lineno}, col #{self.col} in #{self.filename}"
# FIXME: Including self.lineno or self.col seg faults:
    "line #{@lineno}, col #{@col} in #{@filename}"
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

# FIXME: This doesn't work
#    if !ch
# FIXME: The way we currently handle nil, this will crash on an actual null value...
    if ch.nil?
      return nil 
    end

# FIXME: ScannerString is broken -- need to handle String.new with an argument
#  - this again depends on handling default arguments

    s = ScannerString.new
    r = ch.__get_raw
    s.__set_raw(r)

    # This is where I got a "method missing" for #position. because of misallocation in regalloc.rb
    pos = self.position

    puts pos.inspect

    s.position = pos
    # NOTE: Had to update compile_return to @e.save_result to make "return" work
    return s
  end
end

s = Scanner.new(STDIN)

c = s.peek
puts "Got: #{c} (PEEK)"
c = s.get

puts "Got: #{c} (GET)"
puts "Got: #{s.get} (GET2)"
puts "DONE"
