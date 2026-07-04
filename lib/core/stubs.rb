#
# Stubbed out missing pieces
#
#

# FIXME:
# Should auto-generate this so it actually has the correct value...
# However it requires String support to be functional first.
#
__FILE__ = "lib/core/stubs.rb"
__LINE__ = nil


# Set up the 'main' object
#
# FIXME: This is insufficient. E.g. the object is supposed
# to return 'main' as the textual representation.
#
self = Object.new



# FIXME: This is of course just plain blatantly wrong, but
# the next goal is to get everything to link (and crash...)
# These fall in two categories:
#  - The ones that fails because scoped lookups doesn't
#    yet work
E = 2

#  - The ones that fails because they haven't been implemented
# Enumerable=8 #Here because modules doesn't work yet

# raise is now implemented in lib/core/kernel.rb

# FIXME:
%s(defun range (a b)
  (puts "Compiler range construct is not implemented yet")
)

# FIXME
$LOAD_PATH=[]

# FIXME: We'll pick something else for this; for now I just
# need *something* to distinguish from MRI.
RUBY_ENGINE="vidarh/compiler"

# Stub for Thread class (not implemented). Single-threaded: current/main return one
# shared instance, stored in a global rather than a class-level ivar (ivar writes in
# class methods address slots on the CLASS object -- vtable territory). Fixtures
# commonly capture Thread.current at load time and identity-compare it in callbacks
# (e.g. tracepoint's target_thread?); without this every such spec aborted at startup
# before printing a summary, classifying as CRASH.
class Thread
  def self.current
    if !$__thread_current
      $__thread_current = Thread.new
    end
    $__thread_current
  end

  def self.main
    Thread.current
  end
end

# Single-threaded Mutex: with no real threads, lock/unlock just track a flag. Enough for the non-blocking
# specs (locked?/owned?/try_lock/synchronize). Specs that expect ThreadError on misuse (double unlock etc.)
# will FAIL rather than crash, since we don't raise. synchronize avoids begin/ensure (exception handling is
# limited); a raising block simply won't unlock, which is acceptable for a stub.
class Mutex
  def initialize
    @locked = false
  end

  def lock
    @locked = true
    self
  end

  def unlock
    @locked = false
    self
  end

  def locked?
    @locked
  end

  def try_lock
    return false if @locked
    @locked = true
    true
  end

  def owned?
    @locked
  end

  def synchronize
    lock
    r = yield
    unlock
    r
  end

  def sleep(timeout = nil)
    0
  end
end

# Minimal Time: enough that fixture-level `Time.now` / `Time.at` and simple arithmetic and
# comparison run instead of ABORTING whole spec files at load with "uninitialized constant
# Time" (the entire core/time family plus marshal specs died this way). Seconds come from
# libc time() via a raw sexp call. The value is stored REBASED to 2020-01-01 (epoch
# 1577836800): a raw 2026 epoch (~1.78e9) overflows this compiler's tagged 31-bit fixnums.
# to_i re-adds the base (wrapping -- absolute values are only approximate), so intra-process
# arithmetic, ordering, and subtraction behave; absolute wall-clock correctness and all the
# zone/format machinery are out of scope for this stub.
class Time
  def initialize
    %s(assign @sec (__int (sub (time 0) 1577836800)))
  end

  def self.now
    Time.new
  end

  def self.at(sec)
    t = Time.new
    t.__set_rebased(sec.to_i - 1577836800)
    t
  end

  def __set_rebased(s)
    @sec = s
    self
  end

  def __rebased
    @sec
  end

  def to_i
    @sec + 1577836800
  end

  def to_f
    to_i
  end

  def +(other)
    t = Time.new
    t.__set_rebased(@sec + other.to_i)
    t
  end

  def -(other)
    if other.is_a?(Time)
      @sec - other.__rebased
    else
      t = Time.new
      t.__set_rebased(@sec - other.to_i)
      t
    end
  end

  def <=>(other)
    @sec <=> other.__rebased
  end

  def ==(other)
    other.is_a?(Time) && @sec == other.__rebased
  end

  def <(other);  @sec < other.__rebased;  end
  def >(other);  @sec > other.__rebased;  end
  def <=(other); @sec <= other.__rebased; end
  def >=(other); @sec >= other.__rebased; end

  def sec; to_i % 60; end
  def usec; 0; end
  def nsec; 0; end
  def subsec; 0; end

  def utc; self; end
  def gmtime; self; end
  def localtime; self; end
  def utc?; true; end
  def gmt?; true; end

  def inspect
    "#<Time #{to_i}>"
  end

  def to_s
    inspect
  end
end

# Binding stub: there is no runtime scope reflection, so a Binding carries nothing. The class
# and Kernel#binding must EXIST because specs call `binding` at toplevel/describe level
# (main/define_method_spec died at load); its methods (eval, local_variable_get, ...) are
# missing and fail per-test.
class Binding
end

class Object
  def binding
    Binding.new
  end
end

# Signal stub: no signal handling, but Signal.list is called at describe level (signal specs
# died at load). Provide the standard Linux signal map with correct numbers.
module Signal
  def self.list
    { "EXIT" => 0, "HUP" => 1, "INT" => 2, "QUIT" => 3, "ILL" => 4, "TRAP" => 5,
      "ABRT" => 6, "BUS" => 7, "FPE" => 8, "KILL" => 9, "USR1" => 10, "SEGV" => 11,
      "USR2" => 12, "PIPE" => 13, "ALRM" => 14, "TERM" => 15, "CHLD" => 17,
      "CONT" => 18, "STOP" => 19, "TSTP" => 20, "TTIN" => 21, "TTOU" => 22,
      "URG" => 23, "XCPU" => 24, "XFSZ" => 25, "VTALRM" => 26, "PROF" => 27,
      "WINCH" => 28, "IO" => 29, "PWR" => 30, "SYS" => 31 }
  end

  def self.trap(sig, command = nil, &block)
    "DEFAULT"
  end

  def self.signame(num)
    list.each do |name, n|
      return name if n == num
    end
    nil
  end
end

# Marshal stub: binary serialization is unimplemented. The methods raise (rescued per-test by
# the spec harness); the CONSTANT must exist because specs reference `Marshal` in describe
# arguments -- evaluated before any rescue -- which aborted whole files at load.
module Marshal
  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  def self.dump(obj, io = nil, limit = nil)
    raise NotImplementedError.new("Marshal.dump not implemented")
  end

  def self.load(source, proc = nil)
    raise NotImplementedError.new("Marshal.load not implemented")
  end

  def self.restore(source, proc = nil)
    raise NotImplementedError.new("Marshal.restore not implemented")
  end
end

# Stub for Module class
# FIXME: Module should be a superclass of Class, but that requires
# significant refactoring of the object model
class Module
  # Module.nesting returns the lexically-enclosing modules at the call site. We don't track lexical
  # nesting at runtime, so return an empty array: enough for fixtures that merely record it at load
  # time (only nesting_spec checks the actual value).
  def self.nesting
    []
  end

  # A bare `def` whose self is a module installs an instance method directly on the module (no singleton).
  def __def_target
    self
  end

  # Module is a separate class from Class here (Class is NOT a subclass of Module -- see the FIXME
  # above), so a Module instance (e.g. Module.new) does not inherit the reflection methods defined on
  # Class. Provide the common ones so they work on modules too. self is the module; the same vtable/
  # name-offset reflection Class uses applies (a module with methods has a vtable).
  def instance_method(name)
    name = name.to_sym if name.is_a?(String)
    UnboundMethod.new(self, name)
  end

  def method_defined?(name, inherit = true)
    name = name.to_sym if name.is_a?(String)
    voff = Class.method_to_voff[name]
    return false if voff.nil?
    real = false
    %s(assign raw (callm voff __get_raw))
    %s(assign ptr (index self raw))
    %s(if (lt ptr __vtable_thunks_start) (assign real true))
    %s(if (gt ptr __vtable_thunks_end) (assign real true))
    real
  end

  def instance_methods(include_super = true)
    result = []
    m = Class.method_to_voff
    names = m.keys
    i = 0
    n = names.length
    while i < n
      name = names[i]
      voff = m[name]
      real = false
      %s(assign raw (callm voff __get_raw))
      %s(assign ptr (index self raw))
      %s(if (lt ptr __vtable_thunks_start) (assign real true))
      %s(if (gt ptr __vtable_thunks_end) (assign real true))
      result << name if real
      i = i + 1
    end
    result
  end
end

# Stub for Fiber class (not implemented)
class Fiber
end
