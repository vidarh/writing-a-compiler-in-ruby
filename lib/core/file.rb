
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  def self.file?(io)
    # @FIXME; really should stat or something
    # but this is just for bootstrapping.
    io.is_a?(File)
  end

  def path
    @path
  end

  def initialize(path, mode = "r")
    @path = path
    %s(assign rpath (callm path __get_raw))
    %s(assign fd (open rpath 0))

   # FIXME: Error checking
    %s(if (le fd 0) (do
         (printf "Failed to open '%s' got %ld\n" rpath fd)
        (div 0 0)
    ))
    %s(assign fd (__get_fixnum fd))

    super(fd)
  end

  def self.open(path, mode = "r")
    f = File.new(path, mode)
  end

  def self.exists?(path)
    %s(assign rpath (callm path __get_raw))
    %s(assign fd (open rpath 0))
    %s(if (le fd 0) (return false))
    %s(close fd)
    return true
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

  def self.expand_path(path, dir_string = Dir.pwd)
    return path if path[0] == ?/
    if path[0..1] == "./"
      return "#{dir_string}#{path[1..-1]}"
    end
    return path "#{dir_string}/#{path[1..-1]}"
  end
end
