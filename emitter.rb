require 'register'
require 'regalloc'

# Returns the operand-value for a given element.
# If an integer (Fixnum) is given, returns a assembly constant (e.g. 42 -> $42)
# If a Symbol is given, it should be a register (e.g. :eax -> %eax)
# Otherwise, returns its string value.
def to_operand_value(src,flags = nil)
  return int_value(src) if src.is_a?(Integer)
  return "%#{src.to_s}" if src.is_a?(Symbol) || src.is_a?(Register)
  src = src.to_s
  return src[1..-1] if flags == :stripdollar && src[0] == ?$
  return src.to_s
end

# Returns assembly constant for integer-value.
def int_value(param)
  return "$#{param.to_s}"
end


require 'iooutput'
require 'arrayoutput'
require 'peephole'

# Emitter class.
# Emits assembly code for x86 (32 Bit) architecture.
class Emitter
  PTR_SIZE = 4 # Point size in bytes.  We are evil and assume 32bit arch. for now

  attr_accessor :seq

  attr_accessor :basic_main

  # falsy to not output debug data. Symbol to output debug info in a supported format.
  # Currently only :stabs is supported. Defaults to :stabs
  attr_accessor :debug   

  def initialize out = IOOutput.new
    @seq = 0
    @out = Peephole.new(out)
    @basic_main = false
    @section = 0 # Are we in a stabs section?
    @allocator = RegisterAllocator.new

    @debug = :stabs
    @lineno = nil
    @linelabel = 0

    @csi = 92.chr
  end


  # Outputs assembly-comment.
  # Useful for debugging / inspecting generated assembly code.
  #
  # Example:
  #
  # <tt>comment("this is a comment")</tt>
  #
  # -> <tt># this is a comment</tt>
  def comment(str)
    @out.comment(str)
  end


  # Generates code that declares a label as global.
  #
  # Example:
  #
  # <tt>export(:main, :function)</tt>
  #
  # becomes:
  #   .globl main
  #   type main, @function
  def export(label, type = nil)
    @out.export(label,type);
  end

  # Emits rodata-section.
  # Takes a block and calls it after emitting the rodata-section.
  def rodata
    emit(".section", ".rodata")
    yield
  end

  # Emits bss-section.
  # Takes a block and calls it after emitting the bss-section.
  def bss
    emit(".section",".bss")
    emit(".align", "4")
    yield
  end

  # Returns / generates code for adress of given local parameter in %ebp register.
  def local_arg(aparam)
    "#{PTR_SIZE*(aparam+2)}(%ebp)"
  end


  # Returns / generates code for adress of given local variable in %ebp register.
  def local_var(aparam)
    # +2 instead of +1 because %ecx is pushed onto the stack in main,
    # In any variadic function we push :numargs from %ebx into -4(%ebp)
    "-#{PTR_SIZE*(aparam+2)}(%ebp)"
  end


  # Generates code for creating a label in assembly.
  def label(l)
    @out.label(l)
    l
  end


  # Generates a label for a given local variable. If no identifier given, retrieve it via get_local.
  def local(l = nil)
    l = get_local if !l
    label(l)
  end


  # Returns assembly constant for a given parameter.
  def addr_value(param)
    return "$#{param.to_s}"
  end

  def result_value
    return :eax # ster.new(:eax)
  end

  def scratch
    return :ebx #Register.new(:ebx)
  end

  def result
    result_value
  end

  def sp
    return :esp # Register.new(:esp)
  end


  # Store "param" in stack slot "i"
  def save_to_stack(param, i)
    movl(param,"#{i>0 ? i*4 : ""}(%esp)")
  end


  # Stores a given parameter in %eax register as a result for further use.
  def save_result(param)
    if param != :eax
      movl(param, :eax)
    end
  end

  def save_to_reg(param)
    return param if param.is_a?(Symbol)
    movl(param, result_value)
    result_value
  end

  def save(atype, source, dest)
    case atype
    when :reg
      emit(:movl, source,dest) if source != dest
    when :indirect
      emit(:movl,source, "(%#{dest})")
    when :indirect8
      emit(:movb,source, "(%#{dest})")
    when :global
      # Strip the $ prefix from global variable names for assembly
      name = dest.to_s
      name = name[1..-1] if name[0] == ?$
      emit(:movl, source, name)
    when :lvar
      save_to_local_var(source, dest)
    when :ivar
      save_to_instance_var(source, dest)
    when :cvar
      save_to_class_var(source, dest)
    when :arg
      save_to_arg(source, dest)
    when :addr
      save_to_address(source,dest)
    else
      return false
    end
    return true
  end

  def load(atype, aparam,reg = nil)
    case atype
    when :int
      return aparam
    when :strconst
      return addr_value(aparam)
    when :argaddr
      return load_arg_address(aparam)
    when :addr
      return load_address(aparam)
    when :indirect
      return load_indirect(aparam)
    when :indirect8
      return load_indirect8(aparam)
    when :arg
      return load_arg(aparam,reg || result_value)
    when :lvar
      return load_local_var(aparam,reg || result_value)
#    when :ivar
#      return load_instance_var(aparam)
    when :cvar
      return load_class_var(aparam)
    when :global
      return load_global_var(aparam, reg || result_value)
    when :reg
      return aparam if !reg
      comment("LOAD #{aparam}, #{reg}")
      movl(aparam,reg)
      return reg
    when :subexpr
      return result_value
    else
      raise "WHAT? #{atype.inspect} / #{arg.inspect}"
    end
  end

  # Loads an argument into %eax register for further use.
  def load_arg(aparam,reg = result_value)
    movl(local_arg(aparam), reg)
    return reg
  end


  # Loads an arguments adress into %eax register for further use.
  def load_arg_address(aparam)
    leal(local_arg(aparam), result_value)
    return result_value
  end


  def load_global_var(aparam, reg = result_value)
    # Strip the $ prefix from global variable names for assembly
    name = aparam.to_s
    name = name[1..-1] if name[0] == ?$
    movl(name, reg)
    return reg
  end

  def load_local_var(aparam, reg = result_value)
    movl(local_var(aparam), reg)
    return reg
  end

  def load_instance_var(ob, aparam)
    #STDERR.puts "load_instance_var: #{aparam}"
    movl("#{aparam.to_i*PTR_SIZE}(#{to_operand_value(ob)})", result_value)
    return result_value
  end

  def load_class_var(aparam)
    STDERR.puts("Emitter#load_class_var not implemented yet - #{aparam.inspect}")
    # FIXME: uh. yeah. Without fixing the rest the line below 
    # will not return sensible results, but it should let the code compile
    # (and fail)

    return load_global_var(aparam)
  end

  def save_to_local_var(arg, aparam)
    movl(arg,local_var(aparam))
  end

  def save_to_instance_var(arg, ob, aparam)
    movl(arg,"#{aparam.to_i*PTR_SIZE}(#{to_operand_value(ob)})")
  end

  def save_to_class_var(arg, aparam)
    # needs to be implemented
    STDERR.puts("Emitter#save_to_class_var needs to be implemented")
    STDERR.puts("Emitter#save_to_class_var: arg: #{arg.inspect}, aparam: #{aparam.inspect}")
    emit(:movl, arg,aparam.to_s)
  end

  def save_to_arg(arg, aparam)
    movl(arg,local_arg(aparam))
  end

  def save_to_address(src, dest)
    movl(src, dest.to_s)
  end

  def load_address(label)
    save_result(addr_value(label))
    return result_value
  end

  def save_to_indirect(src, dest)
    movl(src,"(%#{dest.to_s})")
  end

  def load_indirect8(arg)
    movzbl("(#{to_operand_value(arg,:stripdollar)})", :eax)
    :eax
  end

  def load_indirect(arg, reg = :eax)
    movl("(#{to_operand_value(arg,:stripdollar)})", reg)
    return reg
  end

  def save_indirect(reg,arg)
    movl(reg, "(#{to_operand_value(arg,:stripdollar)})")
    nil
  end

  # Store a double (8 bytes) at the given address (base + offset)
  # label is the label of a .double in rodata section
  def storedouble(base, offset, label)
    # Load the double value from the label onto the FPU stack and store it
    fldl(label)
    base_str = to_operand_value(base, :stripdollar)
    fstpl("#{offset}(#{base_str})")
    nil
  end

  # Load a double (8 bytes) from the given address (returns in FPU st0, but we don't track that)
  def loaddouble(addr)
    fldl("(#{to_operand_value(addr,:stripdollar)})")
    :st0  # Return symbolic FPU register
  end

  def with_local(args, &block)
    # FIXME: The "+1" is a hack because main contains a pushl %ecx
    with_stack(args+1, &block)
  end

  def with_stack(args, reload_numargs = false, &block)
    # We normally aim to make the stack frame aligned to 16
    # bytes. This however fails in the presence of the splat operator
    # If a splat is present, we instead allocate exact space, and use
    # %ebx to adjust %esp back again afterwards

    if !reload_numargs
      adj = PTR_SIZE * args
    else
      adj = (((args+1) * PTR_SIZE / 16) + 1)* 16
    end

    subl(adj,:esp)
    if !reload_numargs
      addl(args, :ebx)
    else
      movl(args, :ebx)
    end
    yield
    addl(adj, :esp)
  end

  def cached_reg(var)
    @allocator.cached_reg(var)
  end

  def cache_reg!(var, atype, aparam, save = false)
    reg = @allocator.cached_reg(var)

    if (save)
      mark_dirty(var, atype, aparam) if reg
      return reg
    end

    #comment("RA: Already cached '#{reg.to_s}' for #{var}") if reg
    return reg if reg
    reg = @allocator.cache_reg!(var)
    #comment("RA: No available register for #{var}") if !reg
    return nil if !reg
    #comment("RA: Allocated reg '#{reg.to_s}' for #{var}")
    comment([atype,aparam,reg].inspect)
    load(atype,aparam,reg)
    return reg
  end

  def evict_all
    @allocator.evict_all
  end

  def evict_regs_for(vars)
    evicted = @allocator.evict(vars)
    #comment("RA: Evicted #{evicted.join(",")}") if !evicted.empty?
  end

  def with_register(required_reg = nil, &block)
    r = nil
    @allocator.with_register(required_reg) do |reg|
      r = reg
      block.call(reg) #yield reg
    end
    r
  end

  def with_register_for(maybe_reg, &block)
    # @FIXME @bug
    # Because of lack of support for exceptions, this will not work:
    #c = @allocator.lock_reg(maybe_reg) rescue nil
    c = nil
    if maybe_reg.respond_to?(:to_sym)
      c = @allocator.lock_reg(maybe_reg)
    end

    if c
      comment("Locked register #{c.reg}")
      # FIXME: @bug - yield does not work here.
      r = block.call(c.reg) #yield c.reg
      comment("Unlocked register #{c.reg}")
      c.locked = false
      return r
    end
    with_register do |r|
      emit(:movl, maybe_reg, r)
      # FIXME: @bug - yield does not work here.
      block.call(r)
    end
  end

  def mark_dirty(var, type, src)
    reg = cached_reg(var)
    return if !reg
    comment("Marked #{reg} dirty (#{type.to_s},#{src.to_s})")
    @allocator.mark_dirty(reg, lambda do
                            comment("Saving #{reg} to #{type.to_s},#{src.to_s}")
                            save(type, reg, src)
                          end)
  end
  
  # Emits a given operator with possible arguments as an assembly call.
  #
  # Example:
  #   emit(:movl, :esp, :ebp)
  #
  # -> <tt>movl %esp, %ebp</tt>
  def emit(op, *args)
    @out.emit(op, *args)
  end

  def flush
    @out.flush
  end

  # Avoid method_missing...

  def movl src, dest; emit(:movl, src, dest); end
  def addl src, dest; emit(:addl, src, dest); end
  def subl src, dest; emit(:subl, src, dest); end
  def cmpl src, dest; emit(:cmpl, src, dest); end
  def testl src,dest; emit(:testl, src, dest); end
  def movzbl src,dest; emit(:movzbl, src, dest); end
  def andl src, dest; emit(:andl, src, dest); end
  def orl src, dest; emit(:orl, src, dest); end
  def xorl src, dest; emit(:xorl, src, dest); end
  def jmp arg;   emit(:jmp,arg); end
  def popl arg;  emit(:popl, arg); end
  def pushl arg; emit(:pushl, arg); end
  def je arg;    emit(:je, arg); end
  def jz arg;    emit(:jz, arg); end

  def ret; emit(:ret); end
  def leave; emit(:leave); end

  # Floating point instructions
  def fldl src; emit(:fldl, src); end       # Load double onto FPU stack
  def fstpl dest; emit(:fstpl, dest); end   # Store double from FPU stack and pop

  def sall *args
    emit(:sall, *args)
  end
  def sarl *args
    emit(:sarl, *args)
  end
  def idivl *args
    emit(:idivl, *args)
  end
  def divl *args
    emit(:divl, *args)
  end
  def imull *args
    emit(:imull, *args)
  end
  def leal *args
    emit(:leal, *args)
  end

  # Makes it easy to use the emitter to emit any kind of assembly calls, that are needed.
  #
  # Example:
  #   e = Emitter.new
  #   e.emit(:movl, :esp, :ebp)
  #   e.emit(:popl, :ecx)
  def method_missing(sym, *args)
    raise if sym == :reg
    emit(sym, *args)
  end

  # Generates a assembly subroutine call.
  def call(loc)
    @allocator.evict_caller_saved
    if loc.is_a?(Symbol) || loc.is_a?(Register)
      emit(:call, "*"+to_operand_value(loc))
    else
      emit(:call, loc)
    end
  end

  def caller_save
    to_push = @allocator.evict_caller_saved(:will_push)
    to_push.each do |r| 
      self.pushl(r)
      @allocator.free!(r)
    end
    yield
    to_push.reverse.each do |r|
      self.popl(r) 
      @allocator.alloc!(r)
    end
  end

  # Call an entry in a vtable, by default held in %eax
  def callm(off, reg=:eax)
    # FIXME: If there are caller saved registers here that must be
    # saved/reloaded, we need to keep track.
    @allocator.evict_caller_saved
    off = "#{off*Emitter::PTR_SIZE}" if off.is_a?(Integer)

    emit(:call, "*#{off}(%#{reg.to_s})")
  end


  # Generates assembl for defining a string constant.
  def string(l, str)
    local(l)
    if str # nil here is bizarre and probably a bug - it means get_arg() was called with nil
      # FIXME: Should rewrite a lot more thoroughly here...
      buf = ""
      str.each_byte do |b|
        if b < 32 || b == 92
          buf << @csi
          # Zero-pad octal to 3 digits to avoid ambiguity with following digits
          # E.g., \n (10) followed by '2' must be \0122, not \122 (which is 'R')
          octal = b.to_s(8)
          octal = "0" + octal if octal.length == 2
          octal = "00" + octal if octal.length == 1
          buf << octal
        elsif b == 34
          buf << '\"'
        else
          buf << b.chr
        end
      end

      emit(".asciz", "\"#{buf}\"")
    end
  end

  def long(val)
    emit(".long #{val.to_s}")
  end

  def bsslong(l)
    label(l)
    emit(".long 0")
  end


  # Generates code, that jumps to a given label, if the test for op fails.
  def jmp_on_false(label, op = :eax)
    testl(op, op)
    je(label)
  end

  def get_local
    # FIXME: This causes error.
    #@seq +=1
    #".L#{@seq-1}"
    r =  ".L#{@seq}"
    @seq +=1
    return r
  end


  # Generates assembly code for looping.
  # Takes a block, that gets called within the loop.
  def loop
    evict_all
    br = get_local
    l = local
    yield(br,l)
    evict_all
    jmp(l)
    local(br)
  end

  def load_ptr areg,off
    movl("#{off*Emitter::PTR_SIZE}(%#{areg.to_s})", result_value)
  end

  def func(name, position = nil,varfreq= nil, minarty = nil, maxarity = nil, strname = "")
    emit("")
    emit("")
    emit("")

    lspc = (70 - name.length) / 2
    rspc = 70 - name.length - lspc
    
    emit("#{"#"*lspc} #{name} #{"#"*rspc}")
    emit("")



    stabs("\"#{name}:F(0,0)\",36,0,0,#{name}")
    export(name, :function) if name.to_s[0] != ?.
    label(name)

    @funcnum ||= 1
    @curfunc = @funcnum
    @funcnum += 1

    lineno(position) if position
    @out.label(".LFBB#{@curfunc}")

    @allocator.evict_all
    @allocator.order(varfreq)
    @allocator.cache_reg!(:self)
    pushl(:ebp)
    movl(:esp, :ebp)

    pushl(:ebx)  # For numargs
    yield
    popl(:ebx)   # Used in the case of splat args
    leave
    ret

    @allocator.evict_all

    emit(".size", name.to_s, ".-#{name}")
    @scopenum ||= 0
    @scopenum += 1
    label(".Lscope#{@scopenum}")
    stabs("\"\",36,0,0,.Lscope#{@scopenum}-.LFBB#{@curfunc}")
    @curfunc = nil


    emit("")
    emit("#"*72)
    emit("")
    emit("")
    emit("")
    emit("")
  end

  def stabs(str)
    @out.emit(".stabs  #{str}") if @debug == :stabs
  end

  def stabn(str)
    @out.emit(".stabn  #{str}") if @debug == :stabs
  end

  def include(filename)
    @lineno = nil
    return yield if !filename
    @section += 1
    stabs("\"#{filename}\",130,0,0,0")
    ret = yield
    stabn("162,0,0,0")
    @section -= 1
    comment ("End include \"#{filename}\"")
    @lineno = nil
    ret
  end

  def lineno(position)
    if position.lineno != @lineno
      # Annoyingly, the linenumber stabs use relative addresses inside include sections
      # and absolute addresses outside of them.
      #
      if @section == 0
        stabn("68,0,#{position.lineno},.LM#{@linelabel}")
      else
        stabn("68,0,#{position.lineno},.LM#{@linelabel} -.LFBB#{@curfunc}")
      end
      @out.label(".LM#{@linelabel}")
      @linelabel += 1
      @lineno = position.lineno
    end
  end

  # Generates assembly code for the main-function,
  # that gets called when starting the executable.
  # Takes a block, that gets called after some initialization code
  # and before the end of the main-function.
  def main(filename)
    @funcnum = 1
    @curfunc = 0
    if @basic_main
      return yield
    end

    @out.emit(".file \"#{filename}\"")
    stabs("\"#{File.dirname(filename)}/\",100,0,2,.Ltext0")
    stabs("\"#{File.basename(filename)}\",100,0,2,.Ltext0")
    @out.emit(".text")
    @files = [filename]
    label(".Ltext0")
    export(:main, :function)
    label(:main)
    @out.label(".LFBB0")
    pushl(:ebp)
    movl(:esp, :ebp)
    pushl(:ecx)

    yield

    popl(:ecx)
    popl(:ebp)
    ret()
    emit(".size", "main", ".-main")
  end
end
