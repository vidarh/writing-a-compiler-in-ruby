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
