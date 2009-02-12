
class Emitter
  PTR_SIZE = 4 # Point size in bytes.  We are evil and assume 32bit arch. for now

  attr_accessor :seq

  def initialize
    @seq = 0
  end

  def export(label,type=nil)
    puts ".globl #{label}"
    puts "\t.type\t#{label}, @#{type.to_s}"
  end

  def rodata
    emit(".section",".rodata")
    yield
  end

  def local_arg(aparam)
    "#{PTR_SIZE*(aparam+2)}(%ebp)"
  end

  def local_var(aparam)
    # +2 instead of +1 because %ecx is pushed onto the stack in main, 
    # In any variadic function we push :numargs from %ebx into -4(%ebp) 
    "-#{PTR_SIZE*(aparam+2)}(%ebp)"
  end

  def label(l)
    puts "#{l.to_s}:"
    l
  end

  def local(l=nil)
    l = get_local if !l
    label(l)
  end

  def int_value param
    return "$#{param.to_i}"
  end

  def addr_value param
    return "$#{param.to_s}"
  end

  def result_value
    return :eax
  end

  def to_operand_value src
    return int_value(src) if src.is_a?(Fixnum)
    return "%#{src.to_s}" if src.is_a?(Symbol)
    return src.to_s
  end

  # Store "param" in stack slot "i"
  def save_to_stack param,i
    movl(param,"#{i>0 ? i*4 : ""}(%esp)")
  end

  def save_result(param)
    movl(param,:eax) if param != :eax
  end

  def load_arg(aparam)
    movl(local_arg(aparam),:eax)
  end

  def load_local_var(aparam)
    movl(local_var(aparam),:eax)
  end

  def save_to_local_var(arg,aparam)
    movl(arg,local_var(aparam))
  end

  def save_to_arg(arg,aparam)
    movl(arg,local_arg(aparam))
  end

  def load_address(label)
    save_result(addr_value(label))
  end

  def with_local(args)
    # FIXME: The "+1" is a hack because main contains a pushl %ecx
    with_stack(args+1) { yield }
  end

  def with_stack(args,numargs=false)
    # gcc does 4 bytes regardless of arguments, and then jumps up 16 at a time
    # We will do the same, but assume its tied to pointer size
    adj = PTR_SIZE + (((args+0.5)*PTR_SIZE/(4.0*PTR_SIZE)).round) * (4*PTR_SIZE)
    subl(adj,:esp)
    movl(args,:ebx) if numargs
    yield
    addl(adj,:esp)
  end

  def emit op,*args
    puts "\t#{op}\t"+args.collect{|a|to_operand_value(a)}.join(', ')
  end

  def method_missing(sym,*args)
    emit(sym,*args)
  end

  def call loc
    if loc.is_a?(Symbol)
      emit(:call,"*"+to_operand_value(loc))
    else
      emit(:call,loc)
    end
  end
    
  def string l,str
    local(l)
    emit(".string","\"#{str}\"")
  end

  def jmp_on_false(label,op=:eax)
    testl(op,op)
    je(label)
  end

  def get_local
    @seq +=1
    ".L#{@seq-1}"
  end

  def loop
    br = get_local
    l = local
    yield(br)
    jmp(l)
    local(br)
  end

  def func name, save_numargs = false
    export(name,:function) if name.to_s[0] != ?.
    label(name)
    pushl(:ebp)
    movl(:esp,:ebp)
    pushl(:ebx) if save_numargs
    yield
    leave
    ret
    emit(".size",name.to_s, ".-#{name}")
  end

  def main
    puts ".text"
    export(:main,:function)
    label(:main)
    leal("4(%esp)",:ecx)
    andl(-16,:esp)
    pushl("-4(%ecx)")
    pushl(:ebp)
    movl(:esp,:ebp)
    pushl(:ecx)

    yield 

    popl(:ecx)
    popl(:ebp)
    leal("-4(%ecx)",:esp)
    ret()
    emit(".size","main",".-main")
  end
end
