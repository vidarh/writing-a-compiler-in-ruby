class Tempfile
  def initialize(basename = "tmp", tmpdir = nil)
    @basename = basename
  end

  def path
    @path
  end
end
