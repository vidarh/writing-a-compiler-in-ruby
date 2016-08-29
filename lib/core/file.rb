
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  def self.file?(io)
    false
  end

  def initialize(path)
    %s(assign fd (__get_fixnum (open path 0)))

    # FIXME: Error checking

    super(fd)
  end

  def self.open(path)
    f = File.new(path)
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
    path
  end
end
