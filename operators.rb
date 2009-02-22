

Oper = Struct.new(:pri,:sym,:type)

Operators = {
  ","  => Oper.new(2,  :comma,  :infix),

  "="  => Oper.new(6,  :assign, :infix),

  "<"  => Oper.new(9,  :lt,     :infix),
  ">"  => Oper.new(9,  :gt,     :infix),
  "==" => Oper.new(9,  :eq,     :infix),
  "!=" => Oper.new(9,  :ne,     :infix),

  "+"  => Oper.new(10, :add,    :infix),
  "-"  => Oper.new(10, :sub,    :infix),
  "!"  => Oper.new(10, :not,    :prefix),

  "*"  => Oper.new(20, :mul,    :infix),
  "/"  => Oper.new(20, :div,    :infix),
  
  "["  => Oper.new(99, :index,  :infix),
  "]"  => Oper.new(99, nil,     :rp),
  
  "("  => Oper.new(99, nil,     :lp),
  ")"  => Oper.new(99, nil,     :rp)
}

