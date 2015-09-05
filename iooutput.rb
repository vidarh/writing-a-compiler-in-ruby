
#
# Output assembly to IO object
#

class IOOutput
  def initialize out = STDOUT
    @out = out
  end

  def puts str
    @out.puts(str)
  end

  def comment str
    puts "\t# #{str}"
  end

  def label l
    puts "#{l.to_s}:"
  end

  def emit(op, *args)
    puts "\t#{op}\t"+args.collect{ |a| to_operand_value(a) }.join(', ')
  end

  def export(label, type = nil)
    puts ".globl #{label}"
    puts "\t.type\t#{label}, @#{type.to_s}"
  end
end
