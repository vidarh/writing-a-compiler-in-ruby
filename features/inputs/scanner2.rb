
class Scanner
  def initialize(io)
    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, indicate it comes from a stream

    if io.is_a?(File) && File.file?(io)
      @filename = File.expand_path(io.path)
    else
      @filename = "<stream>"
    end

    puts @filename
  end
end

Scanner.new(STDIN)

