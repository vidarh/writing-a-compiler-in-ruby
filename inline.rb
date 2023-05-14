
class Compiler
  # Allow `inline` keyword
  def compile_inline(*args)
    Value.new(:global, :nil)
  end

  def find_inline(exps)
    @inline_functions = {}

    exps.depth_first(:defun) do |e|
      if Array(e[3]).first == :__inline
        body = [].concat(e[4..-1])
        @inline_functions[e[1]] = Function.new(e[1], e[2], body, @e.get_local, false)
      end
    end

    #@inline_classes = {}
    #exps.depth_first(:class) do |e|
    #  #STDERR.puts e
    #end
  end

  # Stupid simple inlining, as starting point.
  def rewrite_inline(exps)
    find_inline(exps)

    #STDERR.puts(@inline_functions.inspect)
    exps.depth_first(:call) do |e|
      f = @inline_functions[e[1]]
      if f
        vars = e[2..-1]
        i = 0
        assigns = []
        while (i < f.args.length)
          assigns << [:assign, f.args[i].name, [:sexp].concat(vars[i])]
          i = i + 1
        end
        body = [:let, f.args.map{|a| a.name}].concat(assigns).concat(f.body)
        #preprocess(body)
        e.replace(body)
        :skip
      else
      end
    end
    exps
  end
end
