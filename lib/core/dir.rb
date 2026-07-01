
class Dir
  def self.pwd
    %s(assign wd (get_current_dir_name))
    %s(assign cwd (__get_string wd))
    cwd = cwd.dup
    %s(free wd)
    return cwd
  end

  # Dir.mkdir(path, mode=0777) -> 0. Creates a single directory (parents must already exist).
  def self.mkdir(path, mode = 511)
    path = path.to_str if !path.is_a?(String)
    %s(assign r (mkdir (callm path __get_raw) (callm mode __get_raw)))
    0
  end

  # Dir.rmdir(path) / delete / unlink -> 0. Removes an empty directory.
  def self.rmdir(path)
    path = path.to_str if !path.is_a?(String)
    %s(rmdir (callm path __get_raw))
    0
  end

  def self.delete(path); rmdir(path); end
  def self.unlink(path); rmdir(path); end

  def self.exist?(path)
    FileTest.directory?(path)
  end
end
