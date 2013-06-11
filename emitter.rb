
# Returns the operand-value for a given element.
# If an integer (Fixnum) is given, returns a assembly constant (e.g. 42 -> $42)
# If a Symbol is given, it should be a register (e.g. :eax -> %eax)
# Otherwise, returns its string value.
def to_operand_value(src,flags = nil)
  return int_value(src) if src.is_a?(Fixnum)
  return "%#{src.to_s}" if src.is_a?(Symbol)
  src = src.to_s
  return src[1..-1] if flags == :stripdollar && src[0] == ?$
  return src.to_s
end

# Returns assembly constant for integer-value.
def int_value(param)
  return "$#{param.to_i}"
end




class IOOutput
  def initialize out = STDOUT
    @out = out
  end

  def puts str
    @out.puts(str)
  end

  def comment str
    puts "\t# #{str}"
  end

  def label l
    puts "#{l.to_s}:"
  end

  def emit(op, *args)
    puts "\t#{op}\t"+args.collect{ |a| to_operand_value(a) }.join(', ')
  end

  def export(label, type = nil)
    puts ".globl #{label}"
    puts "\t.type\t#{label}, @#{type.to_s}"
  end
end

class ArrayOutput
  attr_reader :output

  def initialize 
    @output = []
  end

  def comment str
  end

  def label l
    @output << ["#{l.to_s}"]
  end

  def emit *args
    @output << args
  end

  def export label,type = nil
    @output << [:export,label,type]
  end
end

# Emitter class.
# Emits assembly code for x86 (32 Bit) architecture.
class Emitter
  PTR_SIZE = 4 # Point size in bytes.  We are evil and assume 32bit arch. for now

  attr_accessor :seq

  attr_accessor :basic_main

  def initialize out = IOOutput.new
    @seq = 0
    @out = out
    @basic_main = false
    @section = 0 # Are we in a stabs section?
    @free_registers = [:edx,:ecx]
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
    return :eax
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

  def save(atype, source, dest)
    case atype
    when :indirect
      emit(:movl,source, "(%#{dest})")
    when :global
      emit(:movl, source, dest.to_s)
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

  def load(atype, aparam)
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
    when :arg
      return load_arg(aparam)
    when :lvar
      return load_local_var(aparam)
#    when :ivar
#      return load_instance_var(aparam)
    when :cvar
      return load_class_var(aparam)
    when :global
      return load_global_var(aparam)
    when :subexpr
      return result_value
    else
      raise "WHAT? #{atype.inspect} / #{arg.inspect}"
    end
  end

  # Loads an argument into %eax register for further use.
  def load_arg(aparam)
    movl(local_arg(aparam), :eax)
    return :eax
  end


  # Loads an arguments adress into %eax register for further use.
  def load_arg_address(aparam)
    leal(local_arg(aparam), :eax)
    return :eax
  end


  def load_global_var(aparam)
    movl(aparam.to_s, result_value)
    return result_value
  end

  def load_local_var(aparam)
    movl(local_var(aparam), :eax)
    return :eax
  end

  def load_instance_var(ob, aparam)
    STDERR.puts "load_instance_var: #{aparam}"
    movl("#{aparam.to_i*PTR_SIZE}(#{to_operand_value(ob)})", result_value)
    return result_value
  end

  def load_class_var(aparam)
    STDERR.puts("Emitter#load_class_var not implemented yet - #{aparam.inspect}")
    # FIXME: uh. yeah. Without fixing the rest the line below 
    # will not return sensible results, but it should let the code compile
    # (and fail)
    return result_value
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
  end

  def save_to_arg(arg, aparam)
    movl(arg,local_arg(aparam))
  end

  def save_to_address(src, dest)
    movl(src, dest.to_s)
  end

  def load_address(label)
    save_result(addr_value(label))
    return :eax
  end

  def save_to_indirect(src, dest)
    movl(src,"(%#{dest.to_s})")
  end

  def load_indirect(arg, reg = :eax)
    movl("(#{to_operand_value(arg,:stripdollar)})", reg)
    return reg
  end


  def with_local(args)
    # FIXME: The "+1" is a hack because main contains a pushl %ecx
    with_stack(args+1) { yield }
  end

  def with_stack(args, numargs = false)
    # We normally aim to make the stack frame aligned to 16
    # bytes. This however fails in the presence of the splat operator
    # If a splat is present, we instead allocate exact space, and use
    # %ebx to adjust %esp back again afterwards
    adj = PTR_SIZE + (((args+0.5)*PTR_SIZE/(4.0*PTR_SIZE)).round) * (4*PTR_SIZE)

    # If we're messing with the stack, any registers marked for saving will be
    # saved to avoid having to mess with the stack offsets later
    if @save_register && @save_register.size > 0
      @save_register.each do |r|
        if r[1] == false
          @out.emit(:pushl,r[0])
          r[1] = true
        end
      end
    end

    subl(adj,:esp)
    movl(args, :ebx) if numargs
    yield
    addl(adj, :esp)
  end

  def with_register
    # FIXME: This is a hack - for now we just hand out :edx or :ecx
    # and we don't handle spills.

    @allocated_registers ||= Set.new
    free = @free_registers.shift
    raise "Register allocation FAILED" if !free
    @allocated_registers << free
    yield(free)
    @allocated_registers.delete(free)
    @free_registers << free
  end

  def save_register(reg)
    @save_register ||= []
    @save_register << [reg, false]
    yield
    f = @save_register.pop
    if f[1]
      @out.emit(:popl,f[0])
    end
  end

  # Emits a given operator with possible arguments as an assembly call.
  #
  # Example:
  #   emit(:movl, :esp, :ebp)
  #
  # -> <tt>movl %esp, %ebp</tt>
  def emit(op, *args)
    if @save_register && @save_register.size > 0 && (reg = @save_register.detect{ |r| r[0] == args[1] && r[1] == false })
      @out.emit(:pushl,args[1])
      reg[1] = true
    end
    @out.emit(op, *args)
  end


  # Makes it easy to use the emitter to emit any kind of assembly calls, that are needed.
  #
  # Example:
  #   e = Emitter.new
  #   e.emit(:movl, :esp, :ebp)
  #   e.emit(:popl, :ecx)
  def method_missing(sym, *args)
    emit(sym, *args)
  end


  # Generates a assembly subroutine call.
  def call(loc)
    if loc.is_a?(Symbol)
      emit(:call, "*"+to_operand_value(loc))
    else
      emit(:call, loc)
    end
  end


  # Generates assembl for defining a string constant.
  def string(l, str)
    local(l)
    if str # nil here is bizarre and probably a bug - it means get_arg() was called with nil
      emit(".string", "\"#{str}\"")
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
    @seq +=1
    ".L#{@seq-1}"
  end


  # Generates assembly code for looping.
  # Takes a block, that gets called within the loop.
  def loop
    br = get_local
    l = local
    yield(br)
    jmp(l)
    local(br)
  end

  def func(name, save_numargs = false, position = nil)
    @out.emit(".stabs  \"#{name}:F(0,0)\",36,0,0,#{name}")
    export(name, :function) if name.to_s[0] != ?.
    label(name)

    @funcnum ||= 1
    @curfunc = @funcnum
    @funcnum += 1

    lineno(position) if position
    @out.label(".LFBB#{@curfunc}")

    pushl(:ebp)
    movl(:esp, :ebp)
    pushl(:ebx) if save_numargs
    yield
    leave
    ret
    emit(".size", name.to_s, ".-#{name}")
    @scopenum ||= 0
    @scopenum += 1
    label(".Lscope#{@scopenum}")
    @out.emit(".stabs  \"\",36,0,0,.Lscope#{@scopenum}-.LFBB#{@curfunc}")    
    @curfunc = nil
  end

  def include(filename)
    @section += 1
    @out.emit(".stabs  \"#{filename}\",130,0,0,0")
    ret = yield
    @out.emit(".stabn  162,0,0,0")
    @section -= 1
    comment ("End include \"#{filename}\"")
    ret
  end

  def lineno(position)
    @lineno ||= nil
    @linelabel ||= 0
    if position.lineno != @lineno
      # Annoyingly, the linenumber stabs use relative addresses inside include sections
      # and absolute addresses outside of them.
      #
      if @section == 0
        @out.emit(".stabn  68,0,#{position.lineno},.LM#{@linelabel}")
      else
        @out.emit(".stabn  68,0,#{position.lineno},.LM#{@linelabel} -.LFBB#{@curfunc}")
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
    @out.emit(".stabs \"#{File.dirname(filename)}/\",100,0,2,.Ltext0")
    @out.emit(".stabs \"#{File.basename(filename)}\",100,0,2,.Ltext0")
    @out.emit(".text")
    @files = [filename]
    label(".Ltext0")
    export(:main, :function)
    label(:main)
    @out.label(".LFBB0")
    leal("4(%esp)", :ecx)
    andl(-16, :esp)
    pushl("-4(%ecx)")
    pushl(:ebp)
    movl(:esp, :ebp)
    pushl(:ecx)
  
    yield

    popl(:ecx)
    popl(:ebp)
    leal("-4(%ecx)", :esp)
    ret()
    emit(".size", "main", ".-main")
  end
end
