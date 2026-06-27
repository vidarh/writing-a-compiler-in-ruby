# Minimal Etc: system database accessors (passwd/group lookups return nil here).
module Etc
  def self.getlogin
    "user"
  end

  def self.getpwuid(uid = nil)
    nil
  end

  def self.getpwnam(name)
    nil
  end

  def self.getgrgid(gid = nil)
    nil
  end
end
