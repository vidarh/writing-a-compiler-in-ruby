
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
    emit_row([op, *args])
  end

  SEP = ", ".freeze

  # Takes the already-built [op, *args] instruction row directly. flush() calls this per instruction, so
  # avoiding emit's *args re-collect (and the args.collect intermediate Array) removes two Arrays each.
  def emit_row(row)
    op = row[0]
    s = ""
    i = 1
    len = row.length
    while i < len
      s << SEP if i > 1
      s << to_operand_value(row[i]).to_s
      i += 1
    end
    puts "\t#{op}\t#{s}"
  end

  def export(label, type = nil)
    puts ".globl #{label}"
    puts "\t.type\t#{label}, @#{type.to_s}"
  end

  def flush
  end
end
