
# Process: query methods over the get*id syscalls (all real primitives, so this module references only
# things that already exist -- important, because a module whose methods delegate to missing methods
# perturbs the vtable and regresses unrelated specs). Subprocess operations (spawn/fork/exec/wait/kill)
# are not supported and raise NotImplementedError rather than crash on a missing method.
module Process
  # Values from getpid/getuid/... are small; tagging with __int is safe.
  def self.pid
    v = 0
    %s(assign v (__int (getpid)))
    v
  end

  def self.ppid
    v = 0
    %s(assign v (__int (getppid)))
    v
  end

  def self.uid
    v = 0
    %s(assign v (__int (getuid)))
    v
  end

  def self.euid
    v = 0
    %s(assign v (__int (geteuid)))
    v
  end

  def self.gid
    v = 0
    %s(assign v (__int (getgid)))
    v
  end

  def self.egid
    v = 0
    %s(assign v (__int (getegid)))
    v
  end

  def self.getpgrp
    v = 0
    %s(assign v (__int (getpgrp)))
    v
  end

  # getpgid(pid): the process group of pid; we only model the current group, so return getpgrp.
  def self.getpgid(pid = 0)
    getpgrp
  end

  def self.exit(status = 0)
    %s(exit (callm status __get_raw))
  end

  def self.exit!(status = 0)
    %s(exit (callm status __get_raw))
  end

  def self.abort(msg = nil)
    STDERR.puts(msg) if msg
    %s(exit 1)
  end

  def self.spawn(*args)
    raise NotImplementedError.new("Process.spawn is not supported")
  end

  def self.fork(*args)
    raise NotImplementedError.new("Process.fork is not supported")
  end

  def self.exec(*args)
    raise NotImplementedError.new("Process.exec is not supported")
  end

  def self.wait(*args)
    raise NotImplementedError.new("Process.wait is not supported")
  end

  def self.waitpid(*args)
    raise NotImplementedError.new("Process.waitpid is not supported")
  end

  def self.kill(*args)
    raise NotImplementedError.new("Process.kill is not supported")
  end
end
