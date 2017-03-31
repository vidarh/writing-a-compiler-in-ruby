
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  def self.file?(io)
    false
  end

  def initialize(path, mode = "r")
    %s(assign rpath (callm path __get_raw))
    %s(assign fd (__get_fixnum (open rpath 0)))

    # FIXME: Error checking

    super(fd)
  end

  def self.open(path)
    f = File.new(path)
  end

  def self.basename(name)
    name
  end

  def self.dirname(dname)
    i = dname.rindex(SEPARATOR)
    if !i && ALT_SEPARATOR
      i = dname.rindex(ALT_SEPARATOR)
    end

    if i
      r = 0..i
      d = dname[r]
      return d
    end
    return nil
  end

  def self.expand_path(path)
    STDERR.puts "expand_path: '#{path}'"
    path
  end
end
