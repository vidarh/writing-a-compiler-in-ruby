class Pathname
  def initialize(path)
    @path = path.to_s
  end

  def to_s
    @path
  end

  def to_str
    @path
  end
end
