# Minimal GC module. This compiler's collector (tgc.c) is not introspectable/controllable from Ruby, so
# these are no-ops returning plausible values. Self-contained (no delegation to missing methods), so it is
# safe to add (cf. Set; unlike the FileTest trap). Enough to stop "uninitialized constant GC" crashes and
# let the gc/* specs run (most just check return types / that the call succeeds).
module GC
  def self.start(*args)
    nil
  end

  def self.enable
    false
  end

  def self.disable
    false
  end

  def self.count
    0
  end

  def self.stat(*args)
    {}
  end

  def self.stress
    false
  end

  def self.stress=(value)
    value
  end

  def self.compact
    {}
  end

  def self.measure_total_time
    false
  end

  def self.measure_total_time=(value)
    value
  end

  def self.total_time
    0
  end

  def self.auto_compact
    false
  end

  def self.auto_compact=(value)
    value
  end
end
