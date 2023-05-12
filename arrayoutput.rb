
#
# Output assembly to Array, for e.g. testing
#
class ArrayOutput
  attr_reader :output

  def initialize
    @output = []
  end

  def comment str
  end

  def label l
    @output << ["#{l.to_s}"]
  end

  def emit *args
    @output << args
  end

  def export label,type = nil
    @output << [:export,label,type]
  end

  def flush
  end
end
