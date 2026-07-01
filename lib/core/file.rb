
class File < IO

  SEPARATOR = "/"
  ALT_SEPARATOR = nil

  # POSIX open(2) flags and related constants (Linux x86 values). Referenced directly as File::CREAT,
  # File::WRONLY, etc.; File::Constants re-exposes them for the constants specs.
  RDONLY   = 0
  WRONLY   = 1
  RDWR     = 2
  CREAT    = 64        # 0100
  EXCL     = 128       # 0200
  NOCTTY   = 256       # 0400
  TRUNC    = 512       # 01000
  APPEND   = 1024      # 02000
  NONBLOCK = 2048      # 04000
  SYNC     = 1052672   # 04010000 (O_SYNC)
  LOCK_SH  = 1
  LOCK_EX  = 2
  LOCK_NB  = 4
  LOCK_UN  = 8
  FNM_NOESCAPE = 1
  FNM_PATHNAME = 2
  FNM_DOTMATCH = 4
  FNM_CASEFOLD = 8
  FNM_EXTGLOB  = 16
  FNM_SYSCASE  = 0
  SHARE_DELETE = 0

  # Map a mode argument to open(2) flags. An Integer is used as-is (already flags); a String uses the
  # usual r/w/a (+ optional "+", ignoring "b"/"t") conventions. Anything else defaults to read-only.
  def self.__mode_to_flags(mode)
    return mode if mode.is_a?(Integer)
    return RDONLY if !mode.is_a?(String)
    plus = false
    base = ""
    mode.each_char do |ch|
      if ch == "+"
        plus = true
      elsif ch != "b" && ch != "t"
        base = base + ch if base.length == 0
      end
    end
    if base == "w"
      return plus ? (RDWR | CREAT | TRUNC) : (WRONLY | CREAT | TRUNC)
    elsif base == "a"
      return plus ? (RDWR | CREAT | APPEND) : (WRONLY | CREAT | APPEND)
    elsif base == "r"
      return plus ? RDWR : RDONLY
    end
    RDONLY
  end

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
    flags = File.__mode_to_flags(mode)
    ok = true
    %s(assign rpath (callm path __get_raw))
    # 420 = 0644, the create mode used when O_CREAT is part of the flags.
    %s(assign fd (open rpath (callm flags __get_raw) 420))
    %s(if (lt fd 0) (assign ok false))
    # A missing/inaccessible file used to div-by-zero here; raise the proper Errno instead so specs can
    # rescue it (a create-with-EXCL that finds the file, or opening a nonexistent one for read).
    if !ok
      raise Errno::EEXIST.new("File exists - #{path}") if (flags & File::EXCL) != 0
      raise Errno::ENOENT.new("No such file or directory - #{path}")
    end
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

  # File.chmod(mode, *paths) -> number of paths changed. mode is an integer (e.g. 0644).
  def self.chmod(mode, *paths)
    n = 0
    paths.each do |p|
      p = p.to_str if !p.is_a?(String)
      %s(assign r (chmod (callm p __get_raw) (callm mode __get_raw)))
      n = n + 1
    end
    n
  end

  # File.size(path) -> byte size via stat (st_size at word [11] of the stat buffer).
  def self.size(path)
    path = __coerce_path(path)
    result = -1
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (stat rpath buf))
      (if (eq r 0) (assign result (__int (index buf 11)))))
    raise Errno::ENOENT.new("No such file or directory - #{path}") if result < 0
    result
  end

  # File.link(old, new) -> 0. Creates a hard link. File.symlink(old, new) -> 0. Creates a symlink.
  def self.link(old, new)
    old = __coerce_path(old)
    new = __coerce_path(new)
    %s(link (callm old __get_raw) (callm new __get_raw))
    0
  end

  def self.symlink(old, new)
    old = __coerce_path(old)
    new = __coerce_path(new)
    %s(symlink (callm old __get_raw) (callm new __get_raw))
    0
  end

  def self.unlink(*paths)
    n = 0
    paths.each do |p|
      p = __coerce_path(p)
      %s(unlink (callm p __get_raw))
      n = n + 1
    end
    n
  end

  def self.delete(*paths); unlink(*paths); end

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
  # boundary (so join("a/", "/b") == "a/b", matching MRI closely enough for path building). Array
  # arguments are flattened, as in MRI (File.join("a", ["b", "c"]) == "a/b/c").
  def self.join(*args)
    args = args.flatten
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
    path = __coerce_path(path)
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
    path = __coerce_path(path)
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
    path = __coerce_path(path)
    result = false
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (lstat rpath buf))
      (if (eq r 0) (if (eq (bitand (index buf 4) 61440) 40960) (assign result true))))  # S_IFLNK 0xA000
    result
  end

  # st_size is word [11] of the stat buffer. Returns the byte size, or -1 if stat fails.
  def self.__size(path)
    path = __coerce_path(path)
    result = -1
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (stat rpath buf))
      (if (eq r 0) (assign result (__int (index buf 11)))))
    result
  end

  def self.size(path)
    s = __size(path)
    raise Errno::ENOENT.new("No such file or directory - #{path}") if s < 0
    s
  end

  # size? returns nil when the file is missing OR empty (Ruby semantics), else the size.
  def self.size?(path)
    s = __size(path)
    return nil if s <= 0
    s
  end

  def self.zero?(path);  __size(path) == 0; end
  def self.empty?(path); __size(path) == 0; end

  # identical?(a, b): true if both name the same file -- same device (st_dev, word [0]) and inode
  # (st_ino, word [3]). This is how hard links (and a file vs itself) compare equal.
  def self.identical?(a, b)
    a = __coerce_path(a)
    b = __coerce_path(b)
    same = false
    %s(let (ra rb bufa bufb r1 r2)
      (assign ra (callm a __get_raw))
      (assign rb (callm b __get_raw))
      (assign bufa (__array 40))
      (assign bufb (__array 40))
      (assign r1 (stat ra bufa))
      (assign r2 (stat rb bufb))
      (if (eq r1 0)
        (if (eq r2 0)
          (if (eq (index bufa 0) (index bufb 0))
            (if (eq (index bufa 3) (index bufb 3))
              (assign same true))))))
    same
  end
end
