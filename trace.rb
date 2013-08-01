require 'stringio'

class Compiler

  # Generating trace output for debugging purposes

  def trace(pos,data)
    return false if !@trace
    
    # A bit ugly, but prevents infinite recursion
    # if we accidentally calls anything "traceworthy":
    @trace = false 

    # Save, to minimize risk of interfering with the
    # code.
    @e.pushl(:eax)
    @e.with_stack(2,true) do
        if pos
          pos = pos.short
        end
        sio = StringIO.new
        sio << "#{pos ? pos+":" : "  "} "

        if data.is_a?(String)
          sio << data << "\n"
        else
          print_sexp(data,sio,{:prune => true})
        end
        str = sio.string
        ret = compile_eval_arg(nil,str)
        @e.save_to_stack(ret,0)
        @e.movl([:stderr],:eax)
        @e.save_to_stack(:eax,1)
        @e.call("fputs")
    end
    @e.popl(:eax)
    @trace = true
  end

end
