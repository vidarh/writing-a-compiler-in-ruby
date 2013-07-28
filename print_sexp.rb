
# Print out nicely formatted s-expressions compatible 
# with the compiler.
#
# It should be possible to feed this back into the compiler
# with the appropriate switches

# Class encapsulates some minor state, such as indentation level
class SexpPrinter
  def initialize opts = {}
    @nest = 0
    @indent = 2
    @col = 0
    @maxcol = 120
    @line = 0

    @prune = opts[:prune]
  end

  def indent
    @out.print " "*(@nest * @indent)
    @col += @nest * @indent
  end

  def print str
    str = str.to_s
    if @col > @maxcol
      puts
    end
    indent if @col == 0
    @col += str.length
    @out.print str
  end

  def puts str = ""
    str = str.to_s
    print str if str != ""
    @out.puts if str[-1] != ?\n && @col > 0
    @col = 0
    @line += 1
  end

  def print_tree(data, out = STDOUT)
    @out = out
    print_node(data)
    puts
  end

  def print_node node, nest = 0
    if node.is_a?(Array)
      puts if @col > @maxcol * 0.7 or
        @col > 0 && [:defun,:defm,:class,:if,:let].include?(node.first)
      print "("
      old_line = @line

      if @prune
        if node.first == :class || node.first == :defun || node.first == :module
          node = node[0..2]
          node << "..."
        end
      end

      node.each_with_index do |n,i|
        print " " if i > 0 && @col > 0
        @nest += 1
        puts if n.is_a?(Array) && i == 0
        print_node(n)
        @nest -= 1
        if n == :sexp && i > 0 or node.first == :do or node.first == :let && i > 0
          puts 
        end
      end
      puts if [:defun,:defm,:class].include?(node.first) && @line > old_line
      print ")"
    else
      print node
    end
  end
end

def print_sexp data, out = STDOUT, opts = {}
  SexpPrinter.new(opts).print_tree(data,out)
end
