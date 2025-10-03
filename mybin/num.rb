#!/usr/bin/ruby

require_relative './ansi.rb'
require_relative './utils.rb'

require 'set'

class AnsiString
  def initialize str
    @str = ""
    @attrs = []
    self << str 
  end

  def << str
    fgcol   = nil
    bgcol   = nil
    bold    = nil
    underline = nil
    reverse = nil

    state = nil

    str.split(/(\e\[\d*(?:\;\d+)*m)/).each do |s|
      if s[0] == "\e" && s[1] == "[" && s[-1] == "m"
        attrs = s[2..-2].split(";").collect(&:to_i)
        if attrs.empty?
          attrs << 0
        end

        while !attrs.empty?
          attr = attrs.slice!(0)

          case attr
          when 38, 48
            coltype = attrs.slice!(0)
            if coltype == 5
              col = attrs.pop
            elsif coltype == 2
              col = attrs.slice!(0,3)
            end

            colstr = "#{attr};#{coltype};#{Array(col).join(";")}"
            if attr == 38
              fgcol = colstr
            else
              bgcol = colstr
            end
          when 30..37, 39
            fgcol = attr
          when 40..47, 49
            bgcol = attr
          when 0
            fgcol   = 39
            bgcol   = 49
            bold    = 0
            underline = nil
            reverse = nil
          when 1
            bold = 1
          when 4
            underline = 4
          when 7
            reverse = 7
          else
            puts "WARN: Unknown ANSI attribute: #{attr} (from #{s.inspect})"
          end
        end
      else
          pos = @str.size
          s.each_byte do |ch|
            @str << ch
            @attrs[pos] = [fgcol,bgcol,reverse,underline,bold].compact
            pos += 1
            bold = nil if bold == 0
          end
        end
    end
#    p [@str, @attrs]
  end

  def[] r
    start = r.min
    _end  = r.max
    _end = @str.size - _end + 1 if _end < 0
    _end = @str.size - 1 if _end >= @str.size
    out  = ""
    attr = Set.new
    (start.._end).each do |i|
      a = Set[*@attrs[i]] - attr
      out << "\e[#{a.to_a.sort_by{|c| c.to_i}.join(";")}m" if !a.empty?
      attr = attr + @attrs
      out << @str[i] if @str[i]
    end
    out << "\e[m"
    out
  end

  def rstrip!
    @str.rstrip!
    self
  end
  
  def size
    @str.size
  end
end
    
def num
begin
  cols = TTY.cols - 8
  cnt = 1
  ARGF.each_line do |line|
    line = AnsiString.new(line.chomp.rstrip)
    line.rstrip!
    lcol = line.size
    loff = 0
    first = true
    
    # FIXME: This needs to take into account display width - causes problem w/syntax highlighting,
    
    while loff <= lcol
      if first
        print "#{ANSI.reverse}#{ANSI.blue} #{"%03s" % cnt} #{ANSI.normal} #{line[loff..(loff+cols-1)]}\n"
        
        if lcol > cols
          #print " #{ANSI.blue} >>#{ANSI.normal}"
        end
        first = false
      else
        print "#{ANSI.reverse}#{ANSI.brightblue}     #{ANSI.normal} #{line[loff..(loff+cols)]}\n"
      end
      loff += cols
    end
    cnt += 1
  end
rescue Errno::EPIPE
  puts "Broken pipe"
end

end

num
