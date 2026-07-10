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

  # Proc stores its raw runtime state (code address, captured env, bound self, arity, outer closure) in
  # these ivars; @addr is a raw code pointer, not a Ruby object. Hide them from reflection/Marshal (MRI's
  # Proc#instance_variables is []). Per-class: a *different* class using e.g. @addr is unaffected.
  def __hidden_ivars
    super + [:@addr, :@env, :@s, :@arity, :@closure]
  end

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

  # Function composition: (f >> g).call(x) == g.call(f.call(x)).
  def >>(g)
    f = self
    proc { |*args| g.call(f.call(*args)) }
  end

  # (f << g).call(x) == f.call(g.call(x)).
  def <<(g)
    f = self
    proc { |*args| f.call(g.call(*args)) }
  end

  # Currying: collect arguments across calls until `n` are gathered, then invoke.
  # With no explicit n, use the arity (negative arity -> required count).
  def curry(n = nil)
    ar = n
    if ar.nil?
      ar = arity
      if ar < 0
        ar = 0 - ar - 1
      end
    end
    __curry_step(ar, [])
  end

  def __curry_step(n, got)
    fn = self
    proc do |*args|
      all = got + args
      if all.length >= n
        fn.call(*all)
      else
        fn.__curry_step(n, all)
      end
    end
  end

  def call *__copysplat, &blk
    # ABI slot 2 (__callblk__) carries the CALL-TIME block for the lambda's own &param -- blk
    # here, nil when none. No global channel (re-entrant, thread/fiber-safe). `yield` and
    # block_given? inside the block reach the DEFINING METHOD's block through the env-captured
    # __closure__, so @closure is no longer passed at invocation.
    %s(call @addr (@s blk @env (splat __copysplat)))

    # WARNING: Do not do extra stuff here. If this is a 'proc'/bare block
    # code after the %s(call ...) above will not get executed.
  end

  # Like #call, but invokes the block with `self` bound to `newself` instead of the captured @s. This is
  # the primitive behind class_eval/module_eval/instance_eval and Class.new/Module.new blocks: the block's
  # `def`s (which emit __set_vtable(self, ...)) and self-relative calls (attr_reader, include, ...) then act
  # on `newself`.
  # NOTE: no &blk param here, and none may be added: this method re-expands its splat through the
  # RAW `(splat __copysplat)` s-exp below, whose argument marshalling assumes the signature is
  # exactly (fixed..., *rest) -- an appended &blk made it collect one extra argument. The
  # call-time block therefore travels as the EXPLICIT blkarg fixed parameter (nil when none),
  # which lands in the lambda ABI's __callblk__ slot.
  def __call_with_self newself, blkarg, *__copysplat
    %s(call @addr (newself blkarg @env (splat __copysplat)))
  end

  def [] *__copysplat, &blk
    %s(call @addr (@s blk @env (splat __copysplat)))
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
   # allocate + __set_raw, NOT Proc.new: Proc.new(no block) is allocate + initialize, and initialize sets
   # the five ivars to nil -- which __set_raw immediately overwrites. So the initialize call (and Proc.new's
   # block-check indirection) is pure waste on this hot path (~24.6M/self-compile). allocate gives a blank
   # Proc with slot 0 = the class; __set_raw fills @addr/@env/@s/@arity/@closure. Identical result.
   (assign p (callm Proc allocate))
   (callm p __set_raw (addr env self (__int arity) closure))
   p
))
