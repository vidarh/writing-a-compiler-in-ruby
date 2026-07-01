class Proc
  def initialize
    @addr = nil
    @env  = nil
    @s    = nil  # self in block
    @arity= 0    # Number of arguments.
    @closure = nil  # outer closure for yield support
  end

  # Proc.new { ... } must capture the block it is given and return a callable Proc. The default Class#new
  # (allocate + initialize) drops the block, leaving @addr nil -> calling the result segfaults (null call).
  # The block passed here is ALREADY a Proc (blocks are compiled to Procs via __new_proc), so just return
  # it. The no-block path is the internal __new_proc allocation (`Proc.new` with no block): fall back to a
  # blank allocate+initialize so that path keeps working.
  def self.new(&block)
    return block if block
    p = allocate
    p.initialize
    p
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

  # Like #call, but invokes the block with `self` bound to `newself` instead of the captured @s. This is
  # the primitive behind class_eval/module_eval/instance_eval and Class.new/Module.new blocks: the block's
  # `def`s (which emit __set_vtable(self, ...)) and self-relative calls (attr_reader, include, ...) then act
  # on `newself`.
  def __call_with_self newself, *__copysplat
    %s(call @addr (newself @closure @env (splat __copysplat)))
  end

  def [] *__copysplat
    %s(call @addr (@s @closure @env (splat __copysplat)))
  end

  # Proc#yield is an alias of #call (kept separate rather than a raw duplicate so it does not have the
  # "nothing after the raw call" restriction that #call/#[] have).
  def yield(*args)
    call(*args)
  end

  # Proc#=== invokes the proc, so a proc can act as a case/when condition (`case x; when some_proc`).
  def ===(other)
    call(other)
  end

  # Proc#source_location: [file, line] where the proc was defined. We do not track that yet, so return nil
  # (a valid MRI result for procs with no meaningful location) rather than raising.
  def source_location
    nil
  end

  # Proc#parameters: a description of the proc's parameters. We do not retain parameter metadata after
  # compilation, so return an empty list rather than raising (tests needing real data will fail, not crash).
  def parameters(*)
    []
  end
end

%s(defun __new_proc (addr env self arity closure)
(let (p)
   (assign p (callm Proc new))
   (callm p __set_raw (addr env self (__int arity) closure))
   p
))
