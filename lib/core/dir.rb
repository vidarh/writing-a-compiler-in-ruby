
# Dir: directory streams over opendir/readdir/closedir. A Dir instance holds the raw C DIR* directly in
# @dirp (the same way IO holds its raw @rawbuf) and uses it unwrapped in s-expr; it must NOT be tagged as
# a Ruby Integer, because __int/__get_raw round-trips corrupt any pointer >= 0x40000000 (__get_raw's
# right shift sign-extends). d_name sits at byte offset 11 of the struct dirent returned by readdir here.
class Dir
  def self.pwd
    %s(assign wd (get_current_dir_name))
    %s(assign cwd (__get_string wd))
    cwd = cwd.dup
    %s(free wd)
    return cwd
  end

  def self.getwd; pwd; end

  def self.home(*args)
    ENV["HOME"]
  end

  def self.__chdir_raw(path)
    %s(chdir (callm path __get_raw))
    nil
  end

  # Dir.chdir(path=ENV['HOME']) -> 0. With a block: chdir, yield the path, chdir back, return the block's
  # value. (No ensure: a raising block leaves the cwd changed -- acceptable for the current runtime.)
  def self.chdir(path = nil)
    path = ENV["HOME"] if path.nil?
    path = __coerce_path(path)
    if block_given?
      old = pwd
      __chdir_raw(path)
      r = yield(path)
      __chdir_raw(old)
      return r
    end
    __chdir_raw(path)
    0
  end

  # Dir.mkdir(path, mode=0777) -> 0. Creates a single directory (parents must already exist).
  def self.mkdir(path, mode = 511)
    path = __coerce_path(path)
    %s(assign r (mkdir (callm path __get_raw) (callm mode __get_raw)))
    0
  end

  # Dir.rmdir(path) / delete / unlink -> 0. Removes an empty directory.
  def self.rmdir(path)
    path = __coerce_path(path)
    %s(rmdir (callm path __get_raw))
    0
  end

  def self.delete(path); rmdir(path); end
  def self.unlink(path); rmdir(path); end

  def self.exist?(path)
    FileTest.directory?(path)
  end

  # Dir.entries(path) -> Array of all names in the directory, including "." and "..".
  def self.entries(path)
    d = Dir.new(path)
    result = []
    while (name = d.read)
      result << name
    end
    d.close
    result
  end

  # Dir.children(path) -> entries excluding "." and "..".
  def self.children(path)
    entries(path).reject { |n| n == "." || n == ".." }
  end

  # Dir.each_child(path) { |name| } -> yields each name except "." and "..".
  def self.each_child(path)
    return to_enum(:each_child, path) if !block_given?
    children(path).each { |n| yield n }
    nil
  end

  def self.foreach(path)
    return to_enum(:foreach, path) if !block_given?
    entries(path).each { |n| yield n }
    nil
  end

  def self.empty?(path)
    children(path).empty?
  end

  def self.open(path)
    d = Dir.new(path)
    return d if !block_given?
    r = yield d
    d.close
    r
  end

  def initialize(path)
    @path = __coerce_path(path)
    ok = true
    dp = nil
    %s(assign rp (callm @path __get_raw))
    %s(assign dp (opendir rp))
    %s(if (eq dp 0) (assign ok false))
    raise Errno::ENOENT.new("No such file or directory - #{@path}") if !ok
    @dirp = dp
    @open = true
  end

  def path
    @path
  end

  def to_path
    @path
  end

  # read -> the next entry name (including "." and ".."), or nil at end of stream.
  def read
    return nil if !@open
    name = nil
    %s(assign ent (readdir @dirp))
    %s(if (ne ent 0) (assign name (__get_string (add ent 11))))
    name
  end

  def each
    return to_enum(:each) if !block_given?
    while (name = read)
      yield name
    end
    self
  end

  def children
    result = []
    while (name = read)
      result << name if name != "." && name != ".."
    end
    result
  end

  def each_child
    return to_enum(:each_child) if !block_given?
    while (name = read)
      yield name if name != "." && name != ".."
    end
    self
  end

  def rewind
    if @open
      %s(rewinddir @dirp)
    end
    self
  end

  def tell
    p = 0
    %s(assign p (__int (telldir @dirp)))
    p
  end

  def pos
    tell
  end

  def seek(position)
    if @open
      %s(seekdir @dirp (callm position __get_raw))
    end
    self
  end

  def pos=(position)
    seek(position)
    position
  end

  def close
    if @open
      %s(closedir @dirp)
      @open = false
    end
    nil
  end

  def closed?
    !@open
  end

  def fileno
    f = -1
    if @open
      %s(assign f (__int (dirfd @dirp)))
    end
    f
  end

  def inspect
    "#<Dir:#{@path}>"
  end
end
