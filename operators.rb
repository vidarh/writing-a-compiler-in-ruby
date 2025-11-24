
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
# LARGER numbers mean TIGHTER binding (higher precedence).
class Oper
  attr_accessor :pri, :right_pri, :sym, :type, :arity, :minarity,:assoc

  def initialize(pri, sym, type, arity = nil, minarity = nil, assoc = :right, right_pri = nil)
    @pri = pri
    @right_pri = right_pri || @pri
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

  "if"        => Oper.new(2, :if_mod,   :infix, 2, 2, :right, 1),
  "unless"    => Oper.new(2, :unless_mod, :infix, 2, 2, :right, 1),

  "while"     => Oper.new(2, :while_mod,   :infix, 2, 2, :right, 1),
  "until"     => Oper.new(2, :until_mod,   :infix, 2, 2, :right, 1),
  "for"       => Oper.new(2, :for_stmt,    :infix, 2, 2, :right, 1),

  "rescue"    => Oper.new(2, :rescue_mod, :infix, 2, 2, :right, 1),
  "begin"     => Oper.new(2, :begin_stmt, :prefix, 0, 0),
  "lambda"    => Oper.new(2, :lambda_stmt, :prefix, 0, 0),
  "class"     => Oper.new(2, :class_stmt, :prefix, 0, 0),
  "module"    => Oper.new(2, :module_stmt, :prefix, 0, 0),
#    :infix_or_postfix => 
#    :prefix => Oper.new(1, :while, 1, 0)
#  },

  "break" => Oper.new(22, :break, :prefix, 1, 0, :right, 3),
  "next"  => Oper.new(22, :next,  :prefix, 1, 0, :right, 3),
  "defined?" => Oper.new(0, :defined?, :prefix, nil, nil, :right, 1),  # Very low precedence

  # & is context-sensitive: prefix for block conversion, infix for bitwise AND
  "&"         => {
    :infix_or_postfix => Oper.new( 11, :"&",      :infix, 2, 2, :left),
    :prefix           => Oper.new(  5, :to_block, :prefix)
  },

  # We need assignment operators to have different priority to its left and
  # right due to Ruby grammar weirdess. E.g. && binds looser than = when
  # on its left, and tighter than = when on its right.
  #
  "="         => Oper.new(  7, :assign,   :infix, 2, 2, :right, 5),
  "||="       => Oper.new(  7, :or_assign,:infix, 2, 2, :right, 5),
  "&&="       => Oper.new(  7, :and_assign,:infix, 2, 2, :right, 5),
  "-="        => Oper.new(  7, :decr,     :infix, 2, 2, :right, 5),
  "+="        => Oper.new(  7, :incr,     :infix, 2, 2, :right, 5),
  "*="        => Oper.new(  7, :mul_assign,:infix, 2, 2, :right, 5),
  "/="        => Oper.new(  7, :div_assign,:infix, 2, 2, :right, 5),
  "%="        => Oper.new(  7, :mod_assign,:infix, 2, 2, :right, 5),
  "**="       => Oper.new(  7, :pow_assign,:infix, 2, 2, :right, 5),
  "&="        => Oper.new(  7, :and_bitwise_assign,:infix, 2, 2, :right, 5),
  "|="        => Oper.new(  7, :or_bitwise_assign,:infix, 2, 2, :right, 5),
  "^="        => Oper.new(  7, :xor_assign,:infix, 2, 2, :right, 5),
  "<<="       => Oper.new(  7, :lshift_assign,:infix, 2, 2, :right, 5),
  ">>="       => Oper.new(  7, :rshift_assign,:infix, 2, 2, :right, 5),

  "?"         => Oper.new(  6, :ternif,   :infix),
  "return"    => Oper.new(  6, :return,   :prefix,1,0, :right, 3),

  ":"         => Oper.new(  7, :ternalt,  :infix),
  "&&"        => Oper.new(  7, :and,      :infix),
  "||"        => Oper.new(  6, :or,       :infix),

  "!"         => Oper.new(  8, :"!",      :prefix),
  "not"       => Oper.new(  7, :"!",      :prefix, nil, nil, :right, 99),  # Split precedence: pri=7 (lower than assignment left) but right_pri=99 (forces reduction before method calls)
  "~"         => Oper.new(  8, :"~",      :prefix),
  "<<"        => Oper.new(  8, :<<,       :infix, 2, 2, :left),
  ">>"        => Oper.new(  8, :>>,       :infix, 2, 2, :left),

  # Bitwise operators (in Ruby precedence order: & then ^ then |)
  # Note: & is defined above as context-sensitive

  "^"         => Oper.new( 10, :"^",      :infix, 2, 2, :left),
  "|"         => Oper.new(  9, :"|",      :infix, 2, 2, :left),

  "<"         => Oper.new(  8, :"\<",       :infix),
  "<="        => Oper.new(  8, :"<=",       :infix),
  ">"         => Oper.new(  8, :>,       :infix),
  ">="        => Oper.new(  8, :>=,       :infix),
  "==="       => Oper.new(  8, :===,      :infix),
  "=="        => Oper.new(  8, :==,       :infix),
  "!="        => Oper.new(  8, :"!=",       :infix),
  "<=>"       => Oper.new(  8, :"<=>",      :infix),
  "=~"        => Oper.new(  8, :"=~",       :infix),   # Pattern match
  "!~"        => Oper.new(  8, :"!~",       :infix),   # Negative pattern match

  "+"         => {
    :infix_or_postfix  => Oper.new( 14, :+,      :infix, 2, 2, :left),
    :prefix => Oper.new( 20, :+,      :prefix)
  },
  "-"         => {
    :infix_or_postfix  => Oper.new( 14, :-,      :infix, 2, 2, :left),
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
  "**"        => {
    :infix_or_postfix => Oper.new( 21, :"**",   :infix, 2, 2, :right), # Power/exponentiation (right-associative)
    :prefix           => Oper.new( 8, :hash_splat, :prefix) # Hash spread operator
  },

  # "Fake" operator for function calls
  "#call#"    => Oper.new( 99, :call,     :prefix,2,1),
  "#call2#"   => Oper.new(  9, :call,     :prefix,2,1),
  # Comma has high left precedence (pri=99) but low right precedence (right_pri=8)
  # right_pri must be > assignment's pri (7) to allow destructuring: a,b = c
  # right_pri must be >= prefix operators' pri (8) to allow: when 'f', *arr
  ","         => Oper.new( 99, :comma,    :infix, 2, 1, :left, 8),

  # "Fake" operator for [] following a name
  "#index#"   => Oper.new(100, :index,    :infix),
  "."         => Oper.new( 98, :callm,    :infix, 2,2,:left),
  "&."        => Oper.new( 98, :safe_callm, :infix, 2,2,:left),  # Safe navigation operator (Ruby 2.3+)
  # :: is context-sensitive: prefix for global scope (::Foo), infix for namespace (Foo::Bar)
  "::"        => {
    :prefix => Oper.new(100, :deref, :prefix, 1, 1, :right),
    :infix_or_postfix => Oper.new(100, :deref, :infix, 2, 2, :left)
  },
  ".."        => Oper.new( 97, :range,    :infix, 2, 1), # Support endless ranges (1..) - minarity=1
  "..."       => Oper.new( 97, :exclusive_range, :infix, 2, 1), # Exclusive endless ranges (1...) - minarity=1


  #### Parentheses ####

  "["         => Oper.new( 97, :array,    :lp,1),
  "]"         => Oper.new(  0, nil,       :rp),

  "do"        => Oper.new( 99, :block,    :lp,1),
  "{"         => Oper.new( 99, :hash_or_block, :lp,1),
  "#hash#"    => Oper.new( 99, :hash,     :lp,1),
  "}"         => Oper.new(  0, nil,       :rp),

  "("         => Oper.new( 99, nil,       :lp),
  ")"         => Oper.new(  0, nil,       :rp),

  # Semicolon as statement separator - creates :do blocks
  # Very low priority (1) so it reduces everything before it
  # minarity=0 allows empty statements (do; end, ;expr)
  # Note: Newline as separator is handled specially in tokens.rb to avoid
  # including it in the Operators hash which would cause issues with vtable thunks
  ";"         => Oper.new(  1, :do,       :infix, 2, 0, :left),

}

# Operators that are allowed as method names
OPER_METHOD = %w{=== []= [] == <=> <= >= ** << >> != !~ =~ ! ~ +@ -@ + - * / % & | ^ < >}
