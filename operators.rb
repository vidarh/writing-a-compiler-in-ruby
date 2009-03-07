
class Oper
  attr_accessor :pri,:sym,:type,:arity

  def initialize pri,sym,type,arity = nil
    @pri,@sym,@type = pri,sym,type
    if !arity
      @arity = 0 if type == :lp
      @arity = 1 if type != :lp
      @arity = 2 if type == :infix
    else
      @arity = arity
    end
  end
end

Operators = {
  # "Fake" operator for [] following a name
  "index"  => Oper.new(1,  :index,  :infix),

  # "Fake" operator for function calls
  "call"   => Oper.new(1, :call, :prefix),

  ","  => Oper.new(99,  :comma,  :infix),

  "?"  => Oper.new(7,  :ternif, :infix),
  ":"  => Oper.new(7,  :teralt, :infix),

  "="  => Oper.new(6,  :assign, :infix),

  "<"  => Oper.new(9,  :lt,     :infix),
  ">"  => Oper.new(9,  :gt,     :infix),
  "==" => Oper.new(9,  :eq,     :infix),
  "!=" => Oper.new(9,  :ne,     :infix),
  "+=" => Oper.new(9,  :incr,   :infix),

  "+"  => Oper.new(10, :add,    :infix),
  "-"  => Oper.new(10, :sub,    :infix),
  "!"  => Oper.new(10, :not,    :prefix),

  "*"  => Oper.new(20, :mul,    :infix),
  "/"  => Oper.new(20, :div,    :infix),

  "."  => Oper.new(90, :callm,  :infix),
  
  "["  => Oper.new(99,  :createarray,  :lp,1),
  "]"  => Oper.new(0, nil,     :rp),
  
  "("  => Oper.new(99, nil,     :lp),
  ")"  => Oper.new(0, nil,     :rp)
}

