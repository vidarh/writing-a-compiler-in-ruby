
require 'set'

# Represents Operators within the language.
# An operator is defined by up to 6 components:
#
#  - Priority (pri)
#  - Unique Name / Identifier (sym)
#  - Type (prefix, infix, suffix, left-parenthesis (:lp) or right-parenthesis (:rp))
#  - Arity (how many arguments? Most operators are either unary or binary)
#  - Minarity (The minimum arity, for operators with optional arguments)
#  - Association: Whether the operator binds to the left or right argument first (the default is right)
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

  def inspect
    "{#{@sym}/#{@arity} pri=#{@pri}}"
  end

  def self.expect(s)
    # expect any of the defined operators
    # if operator found, return it's symbol (e.g. "*" -> :*)
    # otherwise simply return nil,
    # as no operator was found by scanner
    #
    # FIXME: Sorting on descending length to ensure longest
    # match. Eventually should replace this by more efficient
    # search, as there are only a handful of possible multi-character
    # operators that collide with single character ones.
    Operators.keys.sort_by {|op| -op.to_s.length}.each do |op|
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
# *mean* anything other than establish order. The only
# reason for gaps is convenience when having to change them
# during development.
#
# FIXME: Currently the priorities and associativity etc. have not been
# systematically validated.
#
Operators = {
  # "Fake" operator injected for blocks.
  "#block#"   => Oper.new(  1, :block,    :infix),
  "#flatten#" => Oper.new(  1, :flatten,  :infix),
  "#,#"       => Oper.new(  1, :comma,    :infix,2,1),
  "or"        => Oper.new(  1, :or,       :infix),
  "and"       => Oper.new(  1, :and,      :infix),

  "=>"        => Oper.new(  5, :pair,     :infix),

  # & is context-sensitive: prefix for block conversion, infix for bitwise AND
  "&"         => {
    :infix_or_postfix => Oper.new( 11, :"&",      :infix, 2, 2, :left),
    :prefix           => Oper.new(  5, :to_block, :prefix)
  },

  "="         => Oper.new(  5, :assign,   :infix),
  "||="       => Oper.new(  5, :or_assign,:infix),
  "-="        => Oper.new(  5, :decr,     :infix),
  "+="        => Oper.new(  5, :incr,     :infix),

  "?"         => Oper.new(  6, :ternif,   :infix),
  "return"    => Oper.new(  6, :return,   :prefix,1,0),

  ":"         => Oper.new(  7, :ternalt,  :infix),
  "&&"        => Oper.new(  7, :and,      :infix),
  "||"        => Oper.new(  6, :or,       :infix),

  "!"         => Oper.new(  8, :"!",      :prefix),
  "~"         => Oper.new(  8, :"~",      :prefix),
  "<<"        => Oper.new(  8, :<<,       :infix, 2, 2, :left),
  ">>"        => Oper.new(  8, :>>,       :infix, 2, 2, :left),

  # Bitwise operators (in Ruby precedence order: & then ^ then |)
  # Note: & is defined above as context-sensitive

  "^"         => Oper.new( 12, :"^",      :infix, 2, 2, :left),
  "|"         => Oper.new( 13, :"|",      :infix, 2, 2, :left),

  "<"         => Oper.new(  9, :"\<",       :infix),
  "<="        => Oper.new(  9, :"<=",       :infix),
  ">"         => Oper.new(  9, :>,       :infix),
  ">="        => Oper.new(  9, :>=,       :infix),
  "==="       => Oper.new(  9, :===,      :infix),
  "=="        => Oper.new(  9, :==,       :infix),
  "!="        => Oper.new(  9, :"!=",       :infix),
  "<=>"       => Oper.new(  9, :"<=>",      :infix),

  "+"         => {
    :infix_or_postfix  => Oper.new( 10, :+,      :infix, 2, 2, :left),
    :prefix => Oper.new( 20, :+,      :prefix)
  },
  "-"         => {
    :infix_or_postfix  => Oper.new( 10, :-,      :infix, 2, 2, :left),
    :prefix => Oper.new( 20, :-,      :prefix)
  },
  "%"         => {
    :infix_or_postfix => Oper.new( 20, :"%",      :infix),
    :prefix => Oper.new( 20, :quoted_exp, :prefix)
  },
  "/"         => Oper.new( 20, :/,      :infix, 2, 2, :left),
  "*"         => {
    :infix_or_postfix => Oper.new( 20, :"*",   :infix, 2, 2, :left),
    :prefix           => Oper.new( 8, :splat, :prefix)
  },
  "**"        => Oper.new( 21, :"**",   :infix, 2, 2, :right), # Power/exponentiation (right-associative)

  # "Fake" operator for function calls
  "#call#"    => Oper.new( 99, :call,     :prefix,2,1),
  "#call2#"   => Oper.new(  9, :call,     :prefix,2,1),
  ","         => Oper.new( 99, :comma,    :infix, 2,1),

  # "Fake" operator for [] following a name
  "#index#"   => Oper.new(100, :index,    :infix),
  "."         => Oper.new( 98, :callm,    :infix, 2,2,:left),
  "::"        => Oper.new(100, :deref,    :infix, 2,2,:left),
  ".."        => Oper.new( 97, :range,    :infix), # FIXME: Check pri; less wrong than it was, but may still not be right
  "..."       => Oper.new( 97, :exclusive_range, :infix), # Exclusive range


  #### Parentheses ####

  "["         => Oper.new( 97, :array,    :lp,1),
  "]"         => Oper.new(  0, nil,       :rp),

  "do"        => Oper.new( 99, :block,    :lp,1),
  "{"         => Oper.new( 99, :hash_or_block, :lp,1),
  "#hash#"    => Oper.new( 99, :hash,     :lp,1),
  "}"         => Oper.new(  0, nil,       :rp),

  "("         => Oper.new( 99, nil,       :lp),
  ")"         => Oper.new(  0, nil,       :rp),

}

# Operators that are allowed as method names
OPER_METHOD = %w{=== []= [] == <=> <= >= ** << >> != !~ =~ ! ~ +@ -@ + - * / % & | ^ < >}
