
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  def self.file?(io)
    false
  end

  def initialize(path, mode = "r")
    STDERR.puts "File.init: #{path.inspect}"
    %s(assign rpath (callm path __get_raw))
    %s(assign fd (open rpath 0))
    %s(perror 0)
   # FIXME: Error checking
    %s(if (le fd 0) (do
         (printf "Failed to open '%s' got %ld\n" rpath fd)
        (div 0 0)
    ))
    %s(assign fd (__get_fixnum fd))

    super(fd)
  end

  def self.open(path)
    f = File.new(path)
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

  def self.expand_path(path)
    STDERR.puts "expand_path: '#{path}'"
    path
  end
end
