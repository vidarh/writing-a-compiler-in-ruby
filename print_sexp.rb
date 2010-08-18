
# Print out nicely formatted s-expressions compatible 
# with the compiler.
#
# It should be possible to feed this back into the compiler
# with the appropriate switches

# Class encapsulates some minor state, such as indentation level
class SexpPrinter
  def initialize
    @nest = 0
    @indent = 2
    @col = 0
    @maxcol = 80
  end

  def indent
    @out.print " "*(@nest * @indent)
    @col += @nest * @indent
  end

  def print str
    str = str.to_s
    if @col > @maxcol
      @out.puts
      @col = 0
    end
    indent if @col == 0
    @col += str.length
    @out.print str
  end

  def puts str = ""
    str = str.to_s
    print str
    @col = 0
    @out.puts if str[-1] != ?\n
  end

  def print_tree(data, out = STDOUT)
    @out = out
    print "%s"
    print_node(data)
    puts
  end

  def print_node node
    if node.is_a?(Array)
      puts if @col > @maxcol * 0.7 or
        @col > 0 && [:defun,:class].include?(node.first)
      print "("
      node.each_with_index do |n,i|
        print " " if i > 0 && @col > 0
        @nest += 1
        puts if n.is_a?(Array) && i == 0
        print_node(n)
        @nest -= 1
        if n == :sexp && i > 0 or
          node.first == :do
          puts 
        end
      end
      puts if [:defun,:class].include?(node.first)
      print ")"
    else
      print node
    end
  end
end

def print_sexp data, out = STDOUT
  SexpPrinter.new.print_tree(data)
end
