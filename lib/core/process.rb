
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

  # Process.spawn(cmd...) -> the child's pid (does NOT wait). Runs cmd via /bin/sh -c. The command
  # strings are held in Ruby locals so the GC keeps their buffers alive for execve.
  def self.spawn(*args)
    cmdstr = args.join(" ")
    sh = "/bin/sh"
    dashc = "-c"
    pid = -1
    %s(do
      (assign kidpid (fork))
      (if (eq kidpid 0)
        (do
          (assign argv (__array 4))
          (assign (index argv 0) (callm sh __get_raw))
          (assign (index argv 1) (callm dashc __get_raw))
          (assign (index argv 2) (callm cmdstr __get_raw))
          (assign (index argv 3) 0)
          (assign envp (__array 1))
          (assign (index envp 0) 0)
          (execve (callm sh __get_raw) argv envp)
          (exit 127))
        (assign pid (__int kidpid))))
    pid
  end

  # Process.waitpid(pid, flags=0) -> the reaped pid (or -1). Process.wait is the same here.
  def self.waitpid(pid, flags = 0)
    result = -1
    %s(do
      (assign stbuf (__array 4))
      (assign r (waitpid (callm pid __get_raw) stbuf (callm flags __get_raw)))
      (assign result (__int r)))
    result
  end

  def self.wait(pid = -1, flags = 0)
    waitpid(pid, flags)
  end

  def self.wait2(pid = -1, flags = 0)
    [waitpid(pid, flags), nil]
  end

  # exec replaces the current process; fork is not exposed as a Ruby-level block fork (needs closures
  # across the fork boundary), so it stays unsupported.
  def self.exec(*args)
    raise NotImplementedError.new("Process.exec is not supported")
  end

  def self.fork(*args)
    raise NotImplementedError.new("Process.fork is not supported")
  end

  def self.kill(*args)
    raise NotImplementedError.new("Process.kill is not supported")
  end
end
