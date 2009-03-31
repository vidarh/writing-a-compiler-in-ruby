
require 'set'

class Oper
  attr_accessor :pri,:sym,:type,:arity, :minarity

  def initialize pri,sym,type,arity = nil, minarity = nil
    @pri,@sym,@type = pri,sym,type
    if !arity
      @arity = 0 if type == :lp
      @arity = 1 if type != :lp
      @arity = 2 if type == :infix
    else
      @arity = arity
    end
    @minarity = minarity || @arity
  end
end

Operators = {
  # "Fake" operator for [] following a name
  "#index#"  => Oper.new(1,  :index,  :infix),

  # "Fake" operator for function calls
  "#call#"   => Oper.new(1, :call, :infix),

  # "Fake" operator injected for blocks.
  "#block#"  => Oper.new(1, :block, :infix),
  "#flatten#" => Oper.new(1, :flatten, :infix),

  ","  => Oper.new(99,  :comma,  :infix),

  "return" => Oper.new(50, :return, :prefix,1,0), #FIXME: Check pri. Also, "return" can also stand on its own
  "or" => Oper.new(5, :or, :infix),
  "&&" => Oper.new(5, :and, :infix), # FIXME: Check pri - probably not right.
  "||" => Oper.new(5, :or, :infix), # FIXME: Check pri - probably not right.

  "?"  => Oper.new(7,  :ternif, :infix),
  ":"  => Oper.new(7,  :ternalt, :infix),

  "="  => Oper.new(6,  :assign, :infix),
  "||=" => Oper.new(6, :or_assign, :infix),
  "-=" => Oper.new(6,  :decr, :infix),
  "+=" => Oper.new(6,  :incr,   :infix),

  "<"  => Oper.new(9,  :lt,     :infix),
  ">"  => Oper.new(9,  :gt,     :infix),
  "==" => Oper.new(9,  :eq,     :infix),
  "!=" => Oper.new(9,  :ne,     :infix),

  "+"  => Oper.new(10, :add,    :infix),
  "-"  => Oper.new(10, :sub,    :infix),
  "!"  => Oper.new(10, :not,    :prefix),

  "*"  => Oper.new(20, :mul,    :infix),
  "/"  => Oper.new(20, :div,    :infix),

  "."  => Oper.new(100, :callm,  :infix),
  "::" => Oper.new(90, :deref,  :infix),
  
  "["  => Oper.new(99,  :createarray,  :lp,1),
  "]"  => Oper.new(0, nil,     :rp),

  "do"  => Oper.new(99, :block,  :lp,1),
  "{"  => Oper.new(99,  :hash_or_block,  :lp,1),
  "#hash#"  => Oper.new(99,  :hash,  :lp,1),
  "}"  => Oper.new(0, nil,     :rp),

  "("  => Oper.new(99, nil,     :lp),
  ")"  => Oper.new(0, nil,     :rp),

  "<<"  => Oper.new(7,  :shiftleft,     :infix), # FIXME: Verify priority
}

