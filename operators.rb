
require 'set'

# Represents Operators within the language.
# An operator is defined by up to 5 components:
#  - Priority (pri)
#  - Unique Name / Identifier (sym)
#  - Type (prefix, infix or suffix)
#  - Arity (how many arguments? Most operators are either unary or binary)
#  - Minarity (The minimum arity, for operators with optional arguments)
#
# The priority defines the precedence-rules for the parser.
# Smaller numbers mean higher priority.
class Oper
  attr_accessor :pri, :sym, :type, :arity, :minarity

  def initialize(pri, sym, type, arity = nil, minarity = nil)
    @pri = pri
    @sym = sym
    @type = type
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


# A hash of all operators within the language.
# The keys are the actual identifiers for each operator.
# The values are the operators themself (instances of the Oper class).
Operators = {
  # "Fake" operator for [] following a name
  "#index#"  => Oper.new(100,  :index,  :infix),

  # "Fake" operator for function calls
  "#call#"   => Oper.new(99, :call, :prefix,2,1),

  # "Fake" operator injected for blocks.
  "#block#"  => Oper.new(1, :block, :infix),
  "#flatten#" => Oper.new(1, :flatten, :infix),

  ","  => Oper.new(99,  :comma,  :infix,2,1),
  "#,#"  => Oper.new(1,  :comma,  :infix,2,1),
  "=>"  => Oper.new(5, :pair,   :infix),

  "return" => Oper.new(50, :return, :prefix,1,0), #FIXME: Check pri. Also, "return" can also stand on its own
  "or" => Oper.new(1, :or, :infix),
  "and" => Oper.new(1, :and, :infix),
  "&&" => Oper.new(6, :and, :infix), # FIXME: Check pri - probably not right.
  "||" => Oper.new(6, :or, :infix), # FIXME: Check pri - probably not right.
  ".." => Oper.new(5, :range, :infix), # FIXME: Check pri - probably not right.

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

  "&"  => Oper.new(5,  :to_block, :prefix), # This will need to be treated like "*" when I add bitwise and.

  "*"  => {
    :infix_or_postfix => Oper.new(20, :mul,    :infix),
    :prefix => Oper.new(100, :splat, :prefix)
  },

  "/"  => Oper.new(20, :div,    :infix),

  "."  => Oper.new(100, :callm,  :infix),
  "::" => Oper.new(90, :deref,  :infix),

  "["  => Oper.new(99,  :array,  :lp,1),
  "]"  => Oper.new(0, nil,     :rp),

  "do"  => Oper.new(99, :block,  :lp,1),
  "{"  => Oper.new(99,  :hash_or_block,  :lp,1),
  "#hash#"  => Oper.new(99,  :hash,  :lp,1),
  "}"  => Oper.new(0, nil,     :rp),

  "("  => Oper.new(99, nil,     :lp),
  ")"  => Oper.new(0, nil,     :rp),

  "<<"  => Oper.new(7,  :shiftleft,     :infix), # FIXME: Verify priority
}

