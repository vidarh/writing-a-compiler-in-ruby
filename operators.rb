
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
  attr_accessor :pri, :sym, :type, :arity, :minarity,:assoc

  def initialize(pri, sym, type, arity = nil, minarity = nil, assoc = :right)
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
    @assoc = assoc
  end

  def self.expect(s)
    # expect any of the defined operators
    # if operator found, return it's symbol (e.g. "*" -> :*)
    # otherwise simply return nil,
    # as no operator was found by scanner
    Operators.keys.each do |op|
      if s.expect(op)
        return op.to_sym
      end
    end
    return nil
  end
end


# A hash of all operators within the language.
# The keys are the actual identifiers for each operator.
# The values are the operators themself (instances of the Oper class).
# The priorities (first argument to Oper.new) does not actually
# *mean* anything - the only reason for gaps is convenience when
# having to change them during development.
Operators = {
  # "Fake" operator injected for blocks.
  "#block#"   => Oper.new(  1, :block,    :infix),
  "#flatten#" => Oper.new(  1, :flatten,  :infix),
  "#,#"       => Oper.new(  1, :comma,    :infix,2,1),
  "or"        => Oper.new(  1, :or,       :infix),
  "and"       => Oper.new(  1, :and,      :infix),

  "=>"        => Oper.new(  5, :pair,     :infix),
  "&"         => Oper.new(  5, :to_block, :prefix), # This will need to be treated like "*" when I add bitwise and.

  "return"    => Oper.new(  6, :return,   :prefix,1,0),
  "&&"        => Oper.new(  6, :and,      :infix),
  "||"        => Oper.new(  6, :or,       :infix),

  "="         => Oper.new(  6, :assign,   :infix),
  "||="       => Oper.new(  6, :or_assign,:infix),
  "-="        => Oper.new(  6, :decr,     :infix),
  "+="        => Oper.new(  6, :incr,     :infix),

  "?"         => Oper.new(  7, :ternif,   :infix),
  ":"         => Oper.new(  7, :ternalt,  :infix),
  "<<"        => Oper.new(  7, :shiftleft,:infix),

  "<"         => Oper.new(  9, :lt,       :infix),
  ">"         => Oper.new(  9, :gt,       :infix),
  "=="        => Oper.new(  9, :eq,       :infix),
  "!="        => Oper.new(  9, :ne,       :infix),


  "+"         => Oper.new( 10, :add,      :infix),
  "-"         => Oper.new( 10, :sub,      :infix),
  "!"         => Oper.new( 10, :not,      :prefix),


  "/"         => Oper.new( 20, :div,      :infix),
  "*"         => {
    :infix_or_postfix => Oper.new( 20, :mul,   :infix),
    :prefix           => Oper.new(100, :splat, :prefix)
  },

  # "Fake" operator for function calls
  "#call#"    => Oper.new( 99, :call,     :prefix,2,1),
  ","         => Oper.new( 99, :comma,    :infix, 2,1),

  # "Fake" operator for [] following a name
  "#index#"   => Oper.new(100, :index,    :infix),
  "."         => Oper.new(100, :callm,    :infix, 2,2,:left),
  "::"        => Oper.new(100, :callm,    :infix, 2,2,:left),
  ".."        => Oper.new(100, :range,    :infix), # FIXME: Check pri - probably not right.


  #### Parentheses ####

  "["         => Oper.new( 99, :array,    :lp,1),
  "]"         => Oper.new(  0, nil,       :rp),

  "do"        => Oper.new( 99, :block,    :lp,1),
  "{"         => Oper.new( 99, :hash_or_block, :lp,1),
  "#hash#"    => Oper.new( 99, :hash,     :lp,1),
  "}"         => Oper.new(  0, nil,       :rp),

  "("         => Oper.new( 99, nil,       :lp),
  ")"         => Oper.new(  0, nil,       :rp),

}

