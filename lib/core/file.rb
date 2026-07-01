
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  def self.file?(io)
    # @FIXME; really should stat or something
    # but this is just for bootstrapping.
    io.is_a?(File)
  end

  def self.absolute_path?(path)
    false
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
    %s(assign fd (__int fd))

    super(fd)
  end

  def self.open(path, mode = "r")
    f = File.new(path, mode)
  end

  def self.exist?(path)
    %s(assign rpath (callm path __get_raw))
    %s(assign fd (open rpath 0))
    %s(if (le fd 0) (return false))
    %s(close fd)
    return true
  end

  def self.readlines(path)
    lines = []
    current_line = ""

    f = File.open(path, "r")
    while c = f.getc
      current_line = current_line + c.chr
      if c == 10  # newline character
        lines << current_line
        current_line = ""
      end
    end

    # Add last line if it doesn't end with newline
    if current_line.length > 0
      lines << current_line
    end

    return lines
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

  # File.join(a, b, ...) -- join path components with SEPARATOR, collapsing a doubled separator at each
  # boundary (so join("a/", "/b") == "a/b", matching MRI closely enough for path building).
  def self.join(*args)
    result = ""
    first = true
    args.each do |arg|
      s = arg.to_s
      if first
        result = s
        first = false
      else
        # NB: String#[int] returns a byte (Integer), so compare against the ?/ char literal, not the
        # SEPARATOR string.
        lhs_sep = result.length > 0 && result[-1] == ?/
        rhs_sep = s.length > 0 && s[0] == ?/
        if lhs_sep && rhs_sep
          result = result + s[1..-1]
        elsif lhs_sep || rhs_sep
          result = result + s
        else
          result = result + SEPARATOR + s
        end
      end
    end
    result
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

# FileTest: filesystem query predicates, implemented over stat/lstat/access (word [4] of the stat
# buffer is st_mode; its top nibble via & 0xF000 is the file type). Real implementations only -- a
# prior FileTest that delegated to missing File methods is why this was long absent.
module FileTest
  # Tagged S_IFMT (file-type) bits of path via stat (follows symlinks), or -1 if stat fails.
  def self.__type(path)
    path = path.to_str if !path.is_a?(String)
    result = -1
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (stat rpath buf))
      (if (eq r 0) (assign result (__int (bitand (index buf 4) 61440)))))
    result
  end

  # True if access(path, mode) succeeds. mode: R_OK=4, W_OK=2, X_OK=1.
  def self.__access(path, mode)
    path = path.to_str if !path.is_a?(String)
    ok = false
    %s(let (rpath r)
      (assign rpath (callm path __get_raw))
      (assign r (access rpath (callm mode __get_raw)))
      (if (eq r 0) (assign ok true)))
    ok
  end

  def self.exist?(path);   File.exist?(path); end
  def self.exists?(path);  File.exist?(path); end
  def self.directory?(path); __type(path) == 16384; end   # S_IFDIR 0x4000
  def self.file?(path);      __type(path) == 32768; end   # S_IFREG 0x8000
  def self.chardev?(path);   __type(path) == 8192;  end   # S_IFCHR 0x2000
  def self.blockdev?(path);  __type(path) == 24576; end   # S_IFBLK 0x6000
  def self.pipe?(path);      __type(path) == 4096;  end   # S_IFIFO 0x1000
  def self.socket?(path);    __type(path) == 49152; end   # S_IFSOCK 0xC000

  def self.readable?(path);        __access(path, 4); end
  def self.readable_real?(path);   __access(path, 4); end
  def self.writable?(path);        __access(path, 2); end
  def self.writable_real?(path);   __access(path, 2); end
  def self.executable?(path);      __access(path, 1); end
  def self.executable_real?(path); __access(path, 1); end

  # symlink? needs lstat (stat follows the link).
  def self.symlink?(path)
    path = path.to_str if !path.is_a?(String)
    result = false
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (lstat rpath buf))
      (if (eq r 0) (if (eq (bitand (index buf 4) 61440) 40960) (assign result true))))  # S_IFLNK 0xA000
    result
  end
end
