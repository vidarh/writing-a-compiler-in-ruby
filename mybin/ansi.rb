
module ANSI

  BOLD = 1
  
  class <<self
    def reverse; "\e[7m"; end

    def black; "\e[30m"; end 
    def red; "\e[31m" end
    def brightred; "\e[31;1m" end
    def brigthgreen; "\e[32;1m"; end
    def green; "\e[32m"; end
    def brightgreen; "\e[32;1m"; end
    def brightyellow;  "\e[33;1m"; end
    def yellow;  "\e[33m"; end
    def blue;  "\e[34m"; end
    def brightblue;  "\e[34;1m"; end
    def purple;  "\e[35m"; end
    def magenta; purple; end
    def brightpurple;  "\e[35;1m"; end
    def brightmagenta; brightpurple; end
    def cyan;  "\e[36m"; end
    def brightcyan;  "\e[36;1m"; end
    def brightwhite; "\e[37;1m"; end
    def white; "\e[37m"; end
    def brightblack;  "\e[30;1m"; end
    
    def normal
      "\e[0m"
    end
  end
end

p __FILE__
p $0

if "out/ansi" == $0 ||  __FILE__ == $0

  def test col
    col = col.to_s
    puts ANSI.send(col)+col + ANSI.normal
  end

  test :black
  test :red
  test :green
  test :yellow
  test :blue
  test :magenta
  test :cyan
  test :white

  test :brightblack
  test :brightred
  test :brightgreen
  test :brightyellow
  test :brightblue
  test :brightmagenta
  test :brightcyan
  test :brightwhite

  #def format(c)
  #  "#{c} \e[#{c}mTest of #{c}" + ANSI.normal
  #end

  def testall
    (0..65).each do |c|
      puts("#{c} \e[#{c}mTest of #{c}"+ANSI.normal)
    end
  end
  testall
end

