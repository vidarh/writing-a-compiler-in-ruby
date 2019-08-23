
class Dir
  def self.pwd
    %s(assign wd (get_current_dir_name))
    %s(assign cwd (__get_string wd))
    cwd = cwd.dup
    %s(free wd)
    return cwd
  end
end
