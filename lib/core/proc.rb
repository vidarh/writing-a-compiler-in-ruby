
class Proc
  def initialize
    @addr = nil
    @env  = nil
    @s    = nil  # self in block
    @arity= 0    # Number of arguments.
  end

  # We do this here rather than allow it to be 
  # set in initialize because we want to 
  # eventually "seal" access to this method
  # away from regular Ruby code

  def __set_raw addr, env, s, arity
    @addr = addr
    @env = env
    @s = s
    @arity = arity
  end

  def arity
    @arity
  end

  def call *arg
    %s(call @addr (@s 0 @env (splat arg)))

    # WARNING: Do not do extra stuff here. If this is a 'proc'/bare block
    # code after the %s(call ...) above will not get executed.
  end
end

%s(defun __new_proc (addr env self arity)
(let (p)
   (assign p (callm Proc new))
   (callm p __set_raw (addr env self (__get_fixnum arity)))
   p
))
