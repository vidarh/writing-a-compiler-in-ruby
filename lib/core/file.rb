
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

  # File class predicates mirror the FileTest module (Ruby exposes both). Delegate to FileTest, which
  # implements them over stat/lstat/access. (FileTest is defined below in this file; a forward reference
  # from a method body is fine since it resolves at call time.)
  # File.file?(path): stat-based for a path (String / #to_path / #to_str). The compiler's own scanner and
  # selftest also call File.file?(io) with a non-path IO/mock object, relying on the historical stub that
  # answered "is this a File instance"; keep that behaviour for non-path arguments.
  def self.file?(path)
    if path.is_a?(String) || path.respond_to?(:to_path) || path.respond_to?(:to_str)
      FileTest.file?(path)
    else
      path.is_a?(File)
    end
  end
  def self.directory?(path);       FileTest.directory?(path);       end
  def self.chardev?(path);         FileTest.chardev?(path);         end
  def self.blockdev?(path);        FileTest.blockdev?(path);        end
  def self.pipe?(path);            FileTest.pipe?(path);            end
  def self.socket?(path);          FileTest.socket?(path);          end
  def self.symlink?(path);         FileTest.symlink?(path);         end
  def self.readable?(path);        FileTest.readable?(path);        end
  def self.readable_real?(path);   FileTest.readable_real?(path);   end
  def self.writable?(path);        FileTest.writable?(path);        end
  def self.writable_real?(path);   FileTest.writable_real?(path);   end
  def self.executable?(path);      FileTest.executable?(path);      end
  def self.executable_real?(path); FileTest.executable_real?(path); end
  def self.zero?(path);            FileTest.zero?(path);            end
  def self.empty?(path);           FileTest.empty?(path);           end
  def self.size?(path);            FileTest.size?(path);            end
  def self.identical?(a, b);       FileTest.identical?(a, b);       end

  def self.absolute_path?(path)
    false
  end

  def path
    @path
  end

  def to_path
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

  # File.open(path, mode="r") -> a File, or with a block yields the File, closes it, and returns the
  # block's value (the ubiquitous `File.open(name) { |f| ... }` idiom). No ensure: a raising block leaves
  # the file open, acceptable for the current runtime.
  # Uses an explicit &blk param (NOT block_given?/yield): a caller forwarding `&b` with b == nil
  # (e.g. Kernel#open's delegation) puts the nil OBJECT in the block slot, which fools
  # block_given? -- but the &blk param binding reads it back as nil, so blk.nil? is correct
  # for both "no block" encodings.
  def self.open(path, mode = "r", &blk)
    f = File.new(path, mode)
    return f if blk.nil?
    result = blk.call(f)
    f.close
    result
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

  # File.mtime(path) -> Time of last modification. st_mtim.tv_sec is at word [16] of the stat buffer
  # (st_size[11], st_blksize[12], st_blocks[13], st_atim[14,15], st_mtim[16,17] in the i386 struct stat).
  def self.mtime(path)
    path = __coerce_path(path)
    # Rebase by the same 2020 epoch Time uses internally: raw st_mtime (~1.78e9) overflows a 30-bit fixnum,
    # but (st_mtime - 1577836800) fits. nil sentinel distinguishes stat-failure from a valid (possibly
    # negative) rebased time. Time#to_i re-adds the epoch (bignum) to yield the true seconds.
    result = nil
    %s(let (rpath buf r)
      (assign rpath (callm path __get_raw))
      (assign buf (__array 40))
      (assign r (stat rpath buf))
      (if (eq r 0) (assign result (__int (sub (index buf 16) 1577836800)))))
    raise Errno::ENOENT.new("No such file or directory - #{path}") if result.nil?
    t = Time.new
    t.__set_rebased(result)
    t
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

  # MRI File.basename: strip trailing separators, take the last component;
  # "/" stays "/". An optional suffix is removed (".*" = any extension).
  def self.basename(name, suffix = nil)
    name = __coerce_path(name)
    e = name.length
    while e > 1 && name[e - 1] == 47      # trailing '/'s (but keep a lone "/")
      e -= 1
    end
    return "/" if e == 1 && name[0] == 47
    s = name[0, e].to_s
    i = s.rindex(SEPARATOR)
    if !i.nil?
      s = s[(i + 1) .. -1].to_s
    end
    if !suffix.nil?
      suffix = __coerce_path(suffix)
      if suffix == ".*"
        d = s.rindex(".")
        if !d.nil? && d > 0
          s = s[0, d].to_s
        end
      elsif suffix.length > 0 && s.length > suffix.length && s.end_with?(suffix)
        s = s[0, s.length - suffix.length].to_s
      end
    end
    s
  end

  # MRI File.dirname: everything before the last component ("." when there is
  # no separator, "/" for root-level paths). level peels multiple components.
  def self.dirname(dname, level = 1)
    raise ArgumentError, "negative level: #{level}" if level < 0
    d = __coerce_path(dname)
    while level > 0
      d = __dirname_one(d)
      level -= 1
    end
    d
  end

  def self.__dirname_one(dname)
    e = dname.length
    while e > 1 && dname[e - 1] == 47     # strip trailing '/'s
      e -= 1
    end
    return "/" if e == 1 && dname[0] == 47
    s = dname[0, e].to_s
    i = s.rindex(SEPARATOR)
    return "." if i.nil?
    while i > 0 && s[i - 1] == 47         # collapse separator run
      i -= 1
    end
    return "/" if i == 0
    s[0, i].to_s
  end

  # Extension of the last component: from the last "." that is neither the
  # component's first byte nor followed by nothing... MRI: "a.rb" -> ".rb",
  # ".profile" -> "", "a" -> "", "a.rb.txt" -> ".txt".
  def self.extname(name)
    b = basename(name)
    d = b.rindex(".")
    return "" if d.nil? || d == 0
    b[d .. -1].to_s
  end

  # [dirname, basename] pair.
  def self.split(name)
    [dirname(name), basename(name)]
  end

  def self.__coerce_path(p)
    return p if p.is_a?(String)
    if p.respond_to?(:to_str)
      r = p.to_str
      return r if r.is_a?(String)
    end
    if p.respond_to?(:to_path)
      r = p.to_path
      return r if r.is_a?(String)
    end
    raise TypeError, "no implicit conversion of #{p.class} into String"
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
