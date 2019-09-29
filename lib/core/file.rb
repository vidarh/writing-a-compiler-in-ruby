
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
    i = name.rindex(SEPARATOR)
    if !i && ALT_SEPARATOR
      i = name.rindex(ALT_SEPARATOR)
    end

    if i
      i = i + 1
      return name[i .. -1]
    end
    return name
  end

  def self.dirname(dname)
    i = dname.rindex(SEPARATOR)
    if !i && ALT_SEPARATOR
      i = dname.rindex(ALT_SEPARATOR)
    end

    if i && i > 0
      i = i - 1
      r = 0..i
      d = dname[r]
      return d
    end
    return nil
  end

  def self.expand_path(path, dir_string = Dir.pwd)
    return path if path[0] == ?/

    str = "#{dir_string}/#{path}".split("/")

    out = []
    str.each do |e|
      if e == "."
        # nop
      elsif e == ""
        # nop
      elsif e == ".."
        out.pop
      else
        out << e
      end
    end

    return "/#{out.join("/")}"
  end
end
