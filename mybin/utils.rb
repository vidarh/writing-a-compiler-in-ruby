
class Shell
  def self.escape(args)
    return args.inspect if !args.respond_to?(:collect)
    # FIXME: Probably not good enough, but works for now
    args.collect{|a| a.inspect }.join(" ")
  end

  def self.system(*args)
    cmd = args.collect {|a| self.escape(a)}.join(" ")
#    STDERR.puts cmd
    Kernel.system(cmd)
  end
end

class String
  def ansilength
    self.split(/\e\[\d+\;?\d*m/).join.length
  end
end

module TTY
  def self.cols
    cols = `tput cols`.to_i
  end
end

