
# RegisterAllocator
#
# We have two principal forms of register usage:
# - temporary intermediate calculations
# - as a "cache" 
#
# These two are in conflict. We maintain a list of
# "possible" registers. 
#
# We then receive a prioritized list of variables
# to cache. The priority is used to determine which
# register to evict first if we run out of free
# registers.
#
# Note that this register allocator is extremely
# simplistic and does not in any way try to take
# into account control flows. The client (Emitter /
# Compiler classes) is expected to ensure the evict_all
# method is called at appropriate places to prevent
# the cache content from being relied on in situations
# where it is invalid (e.g. consider an if ... else .. end
# where a register is put into the cache in the "if" arm,
# in which case relying on this value being present in
# the "else" arm is obviously broken).
#
# We also don't attempt any kind of reordering etc.
# to maximize the utility of the register allocation.
#
# This is, in other words, the bare minimum we can
# get away with to see some benefits.
#
# If no register is free when we want a temporary
# register:
#
# - We evict one of the cached variables.
# - If there are still no registers free, we raise an
#   error for now - it means we're careless about number
#   of registers somewhere. Naughty.
#
#
# SPECIAL CONSIDERATIONS
#
# * Assignment or other mutation:
#
#   Anywhere where the register is mutated, it *must* be
#   marked as dirty, and a suitable spill block must be
#   passed in to write the content back to memory when
#   evicting the register. Note that this also makes it
#   paramount that registers are evicted in any places
#   where writing the contents back is necessary.
#
#   FIXME: We currently will write the content back
#   even if we have passed the last place a variable
#   is actually used.
#
# * Loops:
#
#   Variables allocated outside of the loop must either
#   be allowed to stay in the same register, or be treated as
#   evicted. For now we'll just evict all registers at the
#   start of a loop iteration to avoid dealing with the complexities.
#
# * Lambda etc.
#
#   All variables must be evicted. But we treat lambdas as functions
#   at lower level, so we get that "for free"
# 
# * Aliasing
#
#   If a "let" aliases an outer variable, we need to evict that variable
#   on entry and exit
#
class RegisterAllocator

  # Represents a value cached in a register. For each cached instance,
  # we keep the register name itself as a Symbol, an (optional) block
  # to call when evicting this cached value from the register, that the
  # emitter will use to spill the register back to memory. This is set
  # only if a cached value is "dirtied" (by e.g. an assignment)
  #
  # Cached registers can get evicted at any time. So if we want a
  # temporary register that needs to stay "live", we need to treat it
  # differently. If we have a value that is already in a register, we
  # allow "locking" it into place by setting the "locked" attribute
  # of the cache entry.

  class Cache
    # The register this cache entry is for
    attr_accessor :reg

    # The variable it is cached for
    attr_accessor :var
    
    # The block to call to spill this register if the register is dirty (nil if the register is not dirty)
    attr_accessor :spill

    # True if this cache item can not be evicted because the register is in use.
    attr_accessor :locked

    def initialize reg, var
      @reg = reg.to_sym
      @var = var.to_sym
    end

    # Spill the (presumed dirty) value in the register in question,
    # and assume that the register is no longer dirty. @spill is presumed
    # to contain a block / Proc / object responding to #call that will
    # handle the spill.
    def spill!
      @spill.call if @spill
      @spill = nil
    end
  end


  def initialize
    # This is the list of registers that are available to be allocated
    @registers      = [:edx,:ecx, :edi]

    # Register reserved for "self"
    @selfreg        = :esi

    # Caller saved
    @caller_saved   = [:edx, :ecx, :edi]

    # Initially, all registers start out as free.
    @free_registers = @registers.dup

    @allocated_registers ||= Set.new

    @cached = {}
    @by_reg = {} # Cache information, by register
    @order = {}

    @allocators = []
  end

  # Order to prioritise variables in for register access
  def order f
    @order = f || {}
  end

  # This is primarily for testing, by making the test set of registers
  # independent of the "real"
  def registers= reg
    @registers = reg
    @free_registers = @registers.dup
  end

  def free_registers
    @free_registers.dup
  end

  attr_writer :caller_saved


  def evict_by_cache cache
    return if !cache
    @cached.delete(cache.var)
    r = cache.reg
    debug_is_register?(r)
    cache.spill!
    @by_reg.delete(r)
    @free_registers << r if r != @selfreg
    r ? cache.var : nil
  end

  # Remove any of the variables specified from the set of cached
  # variables, if necessary spilling dirty variables back to memory.
  #
  # FIXME: For now this overrides the "locked" status. I'm not sure
  # if this is safe or not.
  #
  def evict vars
    Array(vars).collect do |v|
      evict_by_cache(@cached[v.to_sym])
    end.compact
  end
  
  def evict_all
    evict(@cached.keys)
  end

  def evict_caller_saved(will_push = false)
    to_push = will_push ? [] : nil
    @caller_saved.each do |r|
      evict_by_cache(@by_reg[r])

      if @allocated_registers.member?(r)
        if !will_push
          raise "Allocated via with_register when crossing call boundary: #{r.inspect}"
        else
          to_push << r
        end
      end
    end
    return to_push
  end

  # Mark this cached register as "dirty". That is, the variable has been
  # updated. In any situation where we evict the variable from this register,
  # we then *must* save the register back to memory.
  def mark_dirty(reg,  block)
    r = @by_reg[reg.to_sym]
    r.spill = block if r
  end

  def debug_is_register?(reg)
    return if reg && reg.to_sym == @selfreg
    raise "NOT A REGISTER: #{reg.to_s}" if !reg || !@registers.member?(reg.to_sym)
  end

  # Called to "cache" a variable in a register. If no register is
  # available, the emitter will use its scratch register (e.g. %eax)
  # instead
  def cache_reg!(var)
    var = var.to_sym

    # Already cached?
    if r = @cached[var]
      return r.reg
    end

    if var == :self
      free = @selfreg
    elsif !@order.member?(var)
      return nil 
    else
      free = @free_registers.shift
    end

    if free
      debug_is_register?(free)
      c = Cache.new(free,var)
      @cached[var.to_sym] = c
      @by_reg[free] = c
    else
      STDERR.puts "NO FREE REGISTER (consider evicting if more important var?)"
    end
    free
  end

  # Return the register allocated to this variable, or nil if none
  # is registered
  def cached_reg(var)
    c = @cached[var.to_sym]
    c ? c.reg : nil
  end

  # Mark this register as locked to the cache, preventing it from
  # being arbitrarily evicted by #with_register
  def lock_reg(reg)
    c = @by_reg[reg.to_sym]
    c.locked=true if c
    c
  end

  # Low level
  def free!(free)
    @allocated_registers.delete(free)
    debug_is_register?(free)
    @free_registers << free
  end

  def alloc!(r)
    @allocated_registers << r
    @free_registers.delete(r)
  end

  # Allocate a temporary register. If specified, we try to allocate
  # a specific register.
  def with_register(required_reg = nil)
    if required_reg
      free = @free_registers.delete(required_reg)
    else
      free = @free_registers.shift
    end

    if !free
      # If no register was immediately free, but one or more
      # registers is in use as cache, see if we can evict one of
      # them.

      if !@cached.empty?
        # Figure out which register to drop, based on order.
        # (least frequently used variable evicted first)
        r = @order.reverse
        r.each do |v|
          # @FIXME: Workaround for @bug below
          if !free
            c = @cached[v]
            if c
              if !c.locked
                # @FIXME
                # @bug variable name matching method name
                # in lambda triggers rewrite bug.
                xreg = c.reg
                evict(v)
                free = xreg
                @free_registers.delete(free)
# @FIXME @bug Break here appears to reset ebx incorrectly.
#              break
             end
           end
          end
        end
      end
    end

    debug_is_register?(free)

    if !free
      # This really should not happen, unless we are
      # very careless about #with_register blocks.

      STDERR.puts "==="
      STDERR.puts @cached.inspect
      STDERR.puts "--"
      STDERR.puts @free_registers.inspect
      STDERR.puts @allocators.inspect
      #raise "Register allocation FAILED"
      1/0
    end

    # This is for debugging of the allocator - we store
    # a backtrace of where in the compiler the allocation
    # was attempted from in case we run out of registers
    # (which we shouldn't)
    @allocators ||= []
    @allocators << caller

    # Mark the register as allocated, to prevent it from
    # being reused.
    @allocated_registers << free

    yield(free)

    # ... and clean up afterwards:

    @allocators.pop
    free!(free)
  end
end

