
class Scanner
  def initialize(io)
    # set filename if io is an actual file (instead of STDIN)
    # otherwhise, indicate it comes from a stream
    @filename = io.is_a?(File) && File.file?(io) ? File.expand_path(io.path) : "<stream>"

    puts @filename
  end
end

Scanner.new(STDIN)

