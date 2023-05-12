
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
    @maxcol = 160
    @brk = 120
    @line = 0

    @prune = opts[:prune]
  end

  def indent
    @out.print " "*(@nest * @indent)
    @col += @nest * @indent
  end

  def print str
    str = str.to_s
    str = str.gsub("\n","\\n")
    if @col > @maxcol
      puts
    end
    indent if @col == 0
    @col += str.length
    @out.print str
  end

  def puts str = ""
    str = str.to_s
    if str != ""
      print str
      # FIXME: The "ord" here is necessary because the compiler
      # itself currently still uses (very) old semantics for string indices.
      @out.puts if str[-1].ord != ?\n
    else
      @out.puts
    end
    @col = 0
    @line += 1
  end

  def print_tree(data, out = STDOUT)
    @out = out
    print "\n%s"
    print_node(data)
    puts
  end

  def print_node node, nest = 0
    if node.respond_to?(:print_node)
      node.print_node(self, nest)
    elsif node.is_a?(Array)
      # FIXME: Changed from @maxcol * 0.7 as compiler currently does not
      # support Float.
      puts if @col > @brk or
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
        if node.first == :do or node.first == :if or node.first == :when or node.first == :case or node.first == :let && i > 0
          puts 
        end
      end
      puts if [:defun,:defm,:class,:do,:case].include?(node.first) && @line > old_line
      print ")"
    elsif node.is_a?(String)
      print "\"#{node}\""
    else
      print node
    end
  end
end

def print_sexp data, out = STDOUT, opts = {}
  SexpPrinter.new(opts).print_tree(data,out)
end
