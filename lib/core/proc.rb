class Proc
  def initialize
    @addr = nil
    @env  = nil
    @s    = nil  # self in block
    @arity= 0    # Number of arguments.
    @closure = nil  # outer closure for yield support
  end

  # We do this here rather than allow it to be
  # set in initialize because we want to
  # eventually "seal" access to this method
  # away from regular Ruby code

  def __set_raw addr, env, s, arity, closure
    @addr = addr
    @env = env
    @s = s
    @arity = arity
    @closure = closure
  end

  def arity
    @arity
  end

  # Returns self - Procs are already procs
  def to_proc
    self
  end

  def call *__copysplat
    %s(call @addr (@s @closure @env (splat __copysplat)))

    # WARNING: Do not do extra stuff here. If this is a 'proc'/bare block
    # code after the %s(call ...) above will not get executed.
  end

  def [] *__copysplat
    %s(call @addr (@s @closure @env (splat __copysplat)))
  end
end

%s(defun __new_proc (addr env self arity closure)
(let (p)
   (assign p (callm Proc new))
   (callm p __set_raw (addr env self (__int arity) closure))
   p
))
